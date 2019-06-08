import UIKit
import AVFoundation
import Photos
import VideoToolbox //def kVTProfileLevel_H264_High_3_1

let sampleRate:Double = 44_100

class ViewController: UIViewController {
    let test:Bool = false // キャプチャー用に静止画を表示
    
    var httpStream:HTTPStream!
    var httpService:HLSService!

    var rtmpConnection:RTMPConnection!
    var rtmpStream:RTMPStream!
    
    var srtConnection:SRTConnection!
    var srtStream:SRTStream!

    @IBOutlet weak var myView: GLHKView!
    
    @IBOutlet weak var segBps:UISegmentedControl!
    @IBOutlet weak var segFps:UISegmentedControl!
    @IBOutlet weak var segZoom:UISegmentedControl!
    
    @IBOutlet weak var btnPublish:CircleButton!
    @IBOutlet weak var btnSettings:RoundRectButton!
    @IBOutlet weak var btnTurn:RoundRectButton!
    @IBOutlet weak var btnOption:RoundRectButton!
    @IBOutlet weak var btnAudio:RoundRectButton!
    @IBOutlet weak var btnFace:RoundRectButton!
    
    var timer:Timer!
    var date1:Date = Date()
    var isPublish:Bool = false
    var isOption:Bool = false

    /// 初期化
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    /// ステータスバー白文字
    override var preferredStatusBarStyle: UIStatusBarStyle {
        return UIStatusBarStyle.lightContent
    }
    
    /// 画面表示
    override func viewWillAppear(_ animated: Bool) {
        logger.info("viewWillAppear")
        super.viewWillAppear(animated)
 
        initControl()
        
        let env = Environment()
        if (env.isHls()) {
            self.httpService = HLSService(domain: "", type: "_http._tcp", name: "my", port: 8080)
            self.httpStream = HTTPStream()
        } else if (env.isRtmp()) {
            self.rtmpConnection = RTMPConnection()
            self.rtmpStream = RTMPStream(connection: rtmpConnection)
        } else if (env.isSrt()) {
            self.srtConnection = .init()
            self.srtStream = SRTStream(srtConnection)
        }
        
        currentStream.syncOrientation = false
        
        print("env.videoHeight \(env.videoHeight)")
        var preset:String = AVCaptureSession.Preset.hd1920x1080.rawValue
        if(env.videoHeight<=540) {
            preset = AVCaptureSession.Preset.iFrame960x540.rawValue
        } else if(env.videoHeight<=720) {
            preset = AVCaptureSession.Preset.hd1280x720.rawValue
        }
        
        currentStream.captureSettings = [
            "sessionPreset": preset,
            "continuousAutofocus": true,
            "continuousExposure": true,
            "fps": env.videoFramerate,
        ]

        // Codec/H264Encoder.swift
        currentStream.videoSettings = [
            "width": env.videoHeight/9 * 16,
            "height": env.videoHeight,
            "profileLevel": kVTProfileLevel_H264_High_3_1,
            "maxKeyFrameIntervalDuration": 2,
            "bitrate": env.videoBitrate * 1024, // Average
            "dataRateLimits": [2000*1024 / 8, 1], // MaxBitrate
        ]
        currentStream.audioSettings = [
            "sampleRate": sampleRate,
            "bitrate": 32 * 1024,
            "muted": (env.audioMode==0) ? true : false,
            //"profile": UInt32(MPEG4ObjectID.AAC_LC.rawValue), err ios12
        ]
        
        let pos:AVCaptureDevice.Position = (env.cameraPosition==0) ? .back : .front
        currentStream.attachCamera(DeviceUtil.device(withPosition:pos)) { error in
            logger.warn(error.description)
        }
        currentStream.attachAudio(AVCaptureDevice.default(for: .audio),
                automaticallyConfiguresApplicationAudioSession: true) { error in
            logger.warn(error.description)
        }
        
        currentStream.orientation = getOrientation()
        myView?.attachStream(currentStream)
        
        NotificationCenter.default.addObserver(
            self,
            selector:#selector(self.onOrientationChange(_:)),
            name: UIDevice.orientationDidChangeNotification, // swift4.2
            object: nil)
        
        // タイマー
        timer = Timer.scheduledTimer(timeInterval: 1.0, target: self, selector:#selector(self.onTimer(_:)), userInfo: nil, repeats: true)
        timer.fire()
    }
    
    /// 画面消去
    override func viewWillDisappear(_ animated: Bool) {
        logger.info("viewWillDisappear")
        super.viewWillDisappear(animated)
        
        timer.invalidate()
        changePublish(publish:false)
        
        NotificationCenter.default.removeObserver(
            self,
            name: UIDevice.orientationDidChangeNotification, // swift4.2
            object: nil)
 
        let env = Environment()
        if (env.isHls()) {
            httpStream.dispose()
        } else if (env.isRtmp()) {
            rtmpStream.close()
            rtmpStream.dispose()
        } else if (env.isSrt()) {
            srtStream.close()
            srtStream.dispose()
        }
    }
    
    var currentStream: NetStream! {
        get {
            let env = Environment()
            if (env.isRtmp()) {
                return rtmpStream
            } else if (env.isSrt()) {
                return srtStream
            } else {
                return httpStream
            }
        }
    }

    /// 配信中は端末の回転を無効にする
    override var shouldAutorotate: Bool {
        get {
            if isPublish == false {
                return true
            } else {
                return false
            }
        }
    }
    
    /// 端末の向きは横方向固定（受け側が縦に対応していないため）
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        get {
            return .landscape
        }
    }

    /// 端末の向きが変わったとき
    @objc func onOrientationChange(_ notification: Notification) {
        if self.isPublish == false {
            currentStream.orientation = getOrientation()
        }
    }

    func getOrientation() -> AVCaptureVideoOrientation {
        let ori1:UIDeviceOrientation = UIDevice.current.orientation
        var ori2:AVCaptureVideoOrientation = .landscapeLeft
        if (ori1 == .landscapeRight) {
            ori2 = .landscapeLeft
        } else if (ori1 == .landscapeLeft) {
            ori2 = .landscapeRight
        } 
        return ori2
    }

    /// パブリッシュ
    @IBAction func publishTouchUpInside(_ sender: UIButton) {
        let publish:Bool = !isPublish
        changePublish(publish:publish)
        
        self.btnPublish.isEnabled = false
        self.btnPublish.layer.borderColor = UIColor(red:0.2,green:0.4,blue:0.8,alpha:1.0).cgColor
        
        DispatchQueue.main.asyncAfter(deadline: .now()+1) {
            self.btnPublish.isEnabled = true
            self.btnPublish.layer.borderColor = UIColor(red:0.0,green:0.0,blue:0.0,alpha:0.5).cgColor
        }
    }
        
    func changePublish(publish: Bool) {
        let env = Environment()
        if (env.isHls()) {
            if (publish == true) {
                httpStream.publish("my")
                httpService.startRunning()
                httpService.addHTTPStream(httpStream)
            } else {
                httpStream.publish(nil)
                httpService.stopRunning()
                httpService.removeHTTPStream(httpStream)
            }
            changePublishControl(b:publish)
        } else if(env.isRtmp()) {
            if (publish == true) {
                rtmpConnection.addEventListener(Event.RTMP_STATUS, selector:#selector(self.rtmpStatusHandler(_:)), observer: self)
                print("uri \(env.getUrl())")
                rtmpConnection.connect(env.getUrl())
            } else {
                rtmpConnection.close()
                rtmpConnection.removeEventListener(Event.RTMP_STATUS, selector:#selector(self.rtmpStatusHandler(_:)), observer: self)
                changePublishControl(b:publish)
            }
        } else if(env.isSrt()) {
            if (publish == true) {
                print("uri \(env.getUrl())")
                srtConnection.connect(URL(string: env.getUrl()))
                srtStream.publish("hoge")
                changePublishControl(b:publish)
            } else {
                srtConnection.close()
                changePublishControl(b:publish)
            }
            
        }
    }

    @objc func rtmpStatusHandler(_ notification:Notification) {
        let e:Event = Event.from(notification)
        if let data:ASObject = e.data as? ASObject, let code:String = data["code"] as? String {
            switch code {
            case RTMPConnection.Code.connectSuccess.rawValue:
                let env = Environment()
                print("key \(env.getKey())")
                rtmpStream!.publish(env.getKey())
                changePublishControl(b:true)
            default:
                break
            }
        }
    }

    func changePublishControl(b:Bool) {
        if (b == true) {
            self.isPublish = true
            btnPublish.setImage(UIImage(named:"Red"), for:UIControl.State())
            date1 = Date()
            aryFps.removeAll(keepingCapacity: true)
            isAutoLow = false
        } else {
            self.isPublish = false
            btnPublish.setImage(UIImage(named:"White"), for:UIControl.State())
        }
    }

    /// フレームレート
    @IBAction func onFpsChanged(_ sender: UISegmentedControl) {
        var fps:Double = 5.0
        switch sender.selectedSegmentIndex {
        case 0: fps = 5.0
        case 1: fps = 10.0
        case 2: fps = 15.0
        case 3: fps = 30.0
        default: break
        }
        let env = Environment()
        env.videoFramerate = Int(fps)
        currentStream.captureSettings["fps"] = fps
    }
    
    /// ビットレート
    @IBAction func onBpsChanged(_ sender: UISegmentedControl) {
        var bps:Int = 250
        switch sender.selectedSegmentIndex {
        case 0: bps = 250;
        case 1: bps = 500;
        case 2: bps = 1000;
        case 3: bps = 2000;
        default: break
        }
        let env = Environment()
        env.videoBitrate = bps
        currentStream.videoSettings["bitrate"] = bps * 1024
        aryFps.removeAll(keepingCapacity: true)
    }
    
    /// 解像度
    @IBAction func onHeightChanged(_ sender: UISegmentedControl) {
        var w:Int = 640
        var h:Int = 360
        switch sender.selectedSegmentIndex {
        case 0: h = 270
        case 1: h = 360
        case 2: h = 540
        case 3: h = 720
        default: break
        }      
        w = (h/9) * 16
        let env = Environment()
        env.videoHeight = h
        currentStream.videoSettings = ["width":w, "height":h]
    }
  
    /// ズーム
    @IBAction func onZoomChanged(_ sender: UISegmentedControl) {
        var zoom:Int = 100
        switch sender.selectedSegmentIndex {
        case 0: zoom = 100
        case 1: zoom = 200
        case 2: zoom = 300
        case 3: zoom = 400
        default: break
        }
        // setZoomFactor（倍率1.0-100.0, アニメ, アニメのスピード）標準カメラは4倍まで
        let env = Environment()
        env.zoom = zoom
        currentStream.setZoomFactor(CGFloat(Double(zoom)/100.0), ramping: true, withRate: 2.0)
    }
    
    /// コントロール初期値
    func initControl()
    {
        let env = Environment()
        switch env.videoBitrate {
        case  250: segBps.selectedSegmentIndex = 0
        case  500: segBps.selectedSegmentIndex = 1
        case 1000: segBps.selectedSegmentIndex = 2
        case 2000: segBps.selectedSegmentIndex = 3
        default: break
        }
        switch env.videoFramerate {
        case  5: segFps.selectedSegmentIndex = 0
        case 10: segFps.selectedSegmentIndex = 1
        case 15: segFps.selectedSegmentIndex = 2
        case 30: segFps.selectedSegmentIndex = 3
        default: break
        }
        switch env.zoom {
        case 100: segZoom.selectedSegmentIndex = 0
        case 200: segZoom.selectedSegmentIndex = 1
        case 300: segZoom.selectedSegmentIndex = 2
        case 400: segZoom.selectedSegmentIndex = 3
        default: break
        }
    }
    
    /// 設定画面
    @IBAction func settingsTouchUpInside(_ sender: UIButton) {
        let vc: UIViewController = SettingsViewController()
        self.present(vc, animated: true, completion: nil)
    }

    /// 反転
    @IBAction func turnTouchUpInside(_ sender: Any) {
        let env = Environment()
        env.cameraPosition = (env.cameraPosition==0) ? 1 : 0
        let pos:AVCaptureDevice.Position = (env.cameraPosition==0) ? .back : .front 
        currentStream.attachCamera(DeviceUtil.device(withPosition: pos)) { error in
            logger.warn(error.description)
        }
    }
    
    /// オーディオ
    @IBAction func audioTouchUpInside(_ sender: Any) { 
        let env = Environment()
        env.audioMode = (env.audioMode==1) ? 0 : 1
        let b:Bool = (env.audioMode==1) ? true : false
        currentStream.audioSettings = [
            "muted": !b,
        ]
        btnAudio.setSwitch(b:b)
    }     
    
    /// 顔
    @IBAction func faceTouchUpInside(_ sender: UIButton) {
        if currentStream.mixer.videoIO.ex.detectType == .none {
            currentStream.mixer.videoIO.ex.detectType = .detectFace
            btnFace.setSwitch(b:true)
        } else {
            currentStream.mixer.videoIO.ex.detectType = .none
            btnFace.setSwitch(b:false)
        }
    }
    
    var labelCpu:ValueLabel = ValueLabel()
    var labelFps:ValueLabel = ValueLabel() // device fps
    var labelRps:ValueLabel = ValueLabel() // rtmp fps
    var labelSec:ValueLabel = ValueLabel()
    var labelBg1:ValueLabel = ValueLabel()
    
    var titleCpu:TitleLabel = TitleLabel()
    var titleFps:TitleLabel = TitleLabel()
    var titleRps:TitleLabel = TitleLabel()
    var titleSec:TitleLabel = TitleLabel()
    
    /// ボタン位置
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // 画面の幅高さ
        // ip5  568 320 (640x1136)
        // ip7  667 375 (750x1334)
        // 10.5 1112 834 (1668x2224)
        let vieww:Int = Int(self.myView.frame.width)
        let viewh:Int = Int(self.myView.frame.height)
        print("w=\(view.frame.width) h=\(view.frame.height) w=\(myView.frame.width) h=\(myView.frame.height)")
        
        let stbar:Int = 0
        let cy = viewh/2
        let btnw = Int(btnSettings.frame.width)

        let p:Int = 10
        let top = p + stbar/2
        let btnx = p + btnw/2
        btnPublish.center = CGPoint(x:vieww-btnx, y:cy)
        btnTurn.center = CGPoint(x:vieww-btnx, y:top+btnw/2)
        btnSettings.center = CGPoint(x:btnx, y:top+btnw/2)
        
        // ボタン
        var bottomy = viewh - p - btnw/2 + stbar/2
        let bw = btnw + 6
        btnOption.center = CGPoint(x:btnx+bw*0, y:bottomy)
        btnAudio.center  = CGPoint(x:btnx+bw*1, y:bottomy)
        btnFace.center   = CGPoint(x:btnx+bw*2, y:bottomy)
        
        // セグメント
        let segw = Int(segBps.frame.width)
        let segx = p + segw/2
        let sh = Int(segBps.frame.height) + 8
        bottomy -= 56
        segBps.center  = CGPoint(x:segx, y:bottomy-sh*2)
        segFps.center  = CGPoint(x:segx, y:bottomy-sh*1)
        segZoom.center = CGPoint(x:segx, y:bottomy-sh*0)
        
        // ラベル
        let ly = Int(btnSettings.center.y)
        titleCpu.text = "CPU"
        titleFps.text = "FPS"
        titleRps.text = ""
        titleSec.text = "Elapsed"
        
        let lx1 = 120
        let lx2 = lx1 + 80
        let lx3 = lx2 + 70
        let lx4 = lx3 + 120
        titleCpu.center = CGPoint(x:lx1, y:ly)
        titleFps.center = CGPoint(x:lx2, y:ly)
        titleSec.center = CGPoint(x:lx3, y:ly)
        titleRps.center = CGPoint(x:lx4, y:ly)
        
        labelCpu.center = CGPoint(x:Int(titleCpu.center.x)-12, y:ly)
        labelFps.center = CGPoint(x:Int(titleFps.center.x)-24, y:ly)
        labelSec.center = CGPoint(x:Int(titleSec.center.x)+32, y:ly)
        labelRps.center = CGPoint(x:Int(titleRps.center.x)-16, y:ly)

        titleSec.isHidden = true
        titleRps.isHidden = true
        
        let cpux1 = Int(titleCpu.frame.minX + 360/2)
        labelBg1.frame.size = CGSize.init(width:360, height:25)
        labelBg1.center = CGPoint(x:cpux1-10, y:ly)
        labelBg1.backgroundColor = UIColor(red:0.0,green:0.0,blue:0.0,alpha:0.3)
        labelBg1.layer.cornerRadius = 4
        labelBg1.clipsToBounds = true
        
        // テスト用背景
        if (test==true) {
            let rect = CGRect(x:0, y:(viewh-(vieww*9/16))/2, width:vieww, height:vieww*9/16)
            let testImage = cropThumbnailImage(image:UIImage(named:"TestImage")!,
                               w:Int(rect.width),
                               h:Int(rect.height))
            let testView = UIImageView(image:testImage)
            testView.frame = rect
            self.myView.addSubview(testView)
            print("test y=\(rect.minY)-\(rect.maxY) w=\(rect.width) h=\(rect.height)")
        }
        
        self.myView.addSubview(labelFps)
        self.myView.addSubview(labelRps)
        self.myView.addSubview(labelCpu)
        self.myView.addSubview(labelSec)
        self.myView.addSubview(titleCpu)
        self.myView.addSubview(titleFps)
        self.myView.addSubview(titleRps)
        self.myView.addSubview(titleSec)
        self.myView.addSubview(labelBg1)
        
        self.myView.bringSubviewToFront(btnSettings)
        self.myView.bringSubviewToFront(btnTurn)
        self.myView.bringSubviewToFront(btnOption)
        self.myView.bringSubviewToFront(btnAudio)
        self.myView.bringSubviewToFront(btnPublish)
        self.myView.bringSubviewToFront(btnFace)
        
        self.myView.bringSubviewToFront(labelBg1)

        self.myView.bringSubviewToFront(labelFps)
        self.myView.bringSubviewToFront(labelRps)
        self.myView.bringSubviewToFront(labelCpu)
        self.myView.bringSubviewToFront(labelSec)
        
        self.myView.bringSubviewToFront(titleCpu)
        self.myView.bringSubviewToFront(titleFps)
        self.myView.bringSubviewToFront(titleRps)
        self.myView.bringSubviewToFront(titleSec)
        
        self.myView.bringSubviewToFront(segBps)
        self.myView.bringSubviewToFront(segFps)
        self.myView.bringSubviewToFront(segZoom)
        
        let env = Environment()
        btnAudio.setSwitch(b:env.audioMode==1)
        
        isOption = true
        optionButton(hidden:true)
    }
    
    /// 画質オプション
    @IBAction func optionTouchUpInside(_ sender: UIButton) {
        isOption = !isOption
        optionButton(hidden:isOption)
    }
    func optionButton(hidden:Bool) {
        btnAudio.hideLeft(b:hidden)
        btnFace.hideLeft(b:hidden)
        segBps.hideLeft(b:hidden)
        segFps.hideLeft(b:hidden)
        segZoom.hideLeft(b:hidden)
    }

    /// タイマー
    var aryFps:[Int] = []
    var isAutoLow:Bool = false
    var nDispCpu = 1
    @objc func onTimer(_ tm: Timer) {
        let env = Environment()
       
        if (isPublish == true) {
            if (env.isRtmp() && rtmpStream != nil && rtmpStream.currentFPS >= 0) {
                // RTMP 自動低画質
                let f:Int = Int(rtmpStream.currentFPS)
                if (env.lowimageMode>0 && f>=2) {
                    aryFps.append(f)
                    if (aryFps.count > 10) {
                        aryFps.removeFirst()
                        var sum:Int=0
                        for (_, element) in aryFps.enumerated() {
                            sum += element
                        }
                        let avg:Int = sum / aryFps.count
                        if (isAutoLow==false && env.videoFramerate-avg >= 5) {
                            rtmpStream.videoSettings["bitrate"] = (env.videoBitrate/2) * 1024
                            aryFps.removeAll(keepingCapacity: true)
                            isAutoLow = true
                        } else if (isAutoLow==true && env.videoFramerate-avg <= 2) {
                            rtmpStream.videoSettings["bitrate"] = (env.videoBitrate) * 1024
                            aryFps.removeAll(keepingCapacity: true)
                            isAutoLow = false
                        }
                    }
                }
            }
        }
        
        // 経過秒
        if (isPublish == true) {
            let elapsed = Int32(Date().timeIntervalSince(date1))
            if elapsed<60 {
                labelSec.text = "\(elapsed)" + "sec"
            } else {
                labelSec.text = "\(elapsed/60)" + "min"
            }
            titleSec.isHidden = false
            // 自動停止
            if (elapsed > env.publishTimeout) {
                changePublish(publish:false) 
            }
        } else {
            titleSec.isHidden = true
            labelSec.text = ""
        }
        
        // 配信方式
        if env.isHls() {
            titleRps.text = "HLS"
            labelRps.text = ""
        } else if env.isRtmp() {
            titleRps.text = "RTMP"
            if rtmpStream != nil {
                labelRps.text = "\(rtmpStream.readyState)"
            } else {
                labelRps.text = ""
            }
        } else if env.isSrt() {
            titleRps.text = "SRT"
            if srtStream != nil {
                labelRps.text = "\(srtStream.readyState)"
            } else {
                labelRps.text = ""
            }
        }
        
        // FPS
        if (env.isRtmp() && rtmpStream != nil && rtmpStream.currentFPS >= 0) {
            // rtmp fps
            labelFps.text = "\(rtmpStream.currentFPS)"
        } else {
            labelFps.text = "\(currentStream.mixer.videoIO.ex.fps)"
        }
        
        // CPU
        nDispCpu += 1
        if nDispCpu >= 2 {
            nDispCpu = 0
            labelCpu.text = "\(getCPUPer())" + "%"
        }
        
        if (test == true) {
            labelFps.text = "30"
            labelCpu.text = "9%"
            labelSec.text = "12min"
            labelRps.text = "29"
            titleRps.isHidden = false
            titleSec.isHidden = false
        }
    }
    
    /// CPU使用率（0-100%）
    var cpuCores:Int = UIDevice.current.cpuCores
    private func getCPUPer() -> Int {
        return Int(Int(getCPUUsage())/cpuCores)
    }
    private func getCPUUsage() -> Float {
        // カーネル処理の結果
        var result: Int32
        var threadList = UnsafeMutablePointer<UInt32>.allocate(capacity: 1)
        var threadCount = UInt32(MemoryLayout<mach_task_basic_info_data_t>.size / MemoryLayout<natural_t>.size)
        var threadInfo = thread_basic_info()
        // スレッド情報を取得
        result = withUnsafeMutablePointer(to: &threadList) {
            $0.withMemoryRebound(to: thread_act_array_t?.self, capacity: 1) {
            task_threads(mach_task_self_, $0, &threadCount)
            }
        }
        if result != KERN_SUCCESS { return 0 }
        // 各スレッドからCPU使用率を算出し合計を全体のCPU使用率とする
        return (0 ..< Int(threadCount))
            // スレッドのCPU使用率を取得
            .compactMap { index -> Float? in
                var threadInfoCount = UInt32(THREAD_INFO_MAX)
                result = withUnsafeMutablePointer(to: &threadInfo) {
                    $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                        thread_info(threadList[index], UInt32(THREAD_BASIC_INFO), $0, &threadInfoCount)
                    }
                }
                // スレッド情報が取れない = 該当スレッドのCPU使用率を0とみなす(基本nilが返ることはない)
                if result != KERN_SUCCESS { return nil }
                let isIdle = threadInfo.flags == TH_FLAGS_IDLE
                // CPU使用率がスケール調整済みのため`TH_USAGE_SCALE`で除算し戻す
                return !isIdle ? (Float(threadInfo.cpu_usage) / Float(TH_USAGE_SCALE)) * 100 : nil
            }
            // 合計算出
            .reduce(0, +)
    }

    /// クロップ
    func cropThumbnailImage(image :UIImage, w:Int, h:Int) ->UIImage {
        // リサイズ処理
        let origRef    = image.cgImage
        let origWidth  = Int(origRef!.width)
        let origHeight = Int(origRef!.height)
        var resizeWidth:Int = 0, resizeHeight:Int = 0
        
        if (origWidth < origHeight) {
            resizeWidth = w
            resizeHeight = origHeight * resizeWidth / origWidth
        } else {
            resizeHeight = h
            resizeWidth = origWidth * resizeHeight / origHeight
        }
        
        let resizeSize = CGSize.init(width: CGFloat(resizeWidth), height: CGFloat(resizeHeight))
        UIGraphicsBeginImageContext(resizeSize)
        image.draw(in: CGRect.init(x: 0, y: 0, width: CGFloat(resizeWidth), height: CGFloat(resizeHeight)))
        let resizeImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        // 切り抜き処理
        let cropRect  = CGRect.init(x: CGFloat((resizeWidth - w) / 2), y: CGFloat((resizeHeight - h) / 2), width: CGFloat(w), height: CGFloat(h))
        let cropRef   = resizeImage!.cgImage!.cropping(to: cropRect)
        let cropImage = UIImage(cgImage: cropRef!)
        return cropImage
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
}

//------------------------------------------------------------
// Control
//------------------------------------------------------------
class TitleLabel: UILabel {
    required init(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)!
    }
    override init(frame: CGRect) {
        super.init(frame: frame)
        self.font = UIFont.systemFont(ofSize:16)
        self.textAlignment = .left
        self.frame.size = CGSize.init(width:80, height:25)
        self.textColor = UIColor.green
    }
}

class ValueLabel: UILabel {
    required init(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)!
    }
    override init(frame: CGRect) {
        super.init(frame: frame)
        self.font = UIFont.systemFont(ofSize:16)
        self.textAlignment = .right
        self.frame.size = CGSize.init(width:80, height:25)
        self.textColor = UIColor.white
    }
}

extension UIControl {
    public func hideLeft(b:Bool) {
        if (b==true) {
            UIView.animate(withDuration: 0.2, delay: 0.0, animations: {
                self.center.x -= 20
                self.alpha = 0
            }){_ in
                self.isHidden = b
            }
        } else {
            self.isHidden = b
            UIView.animate(withDuration: 0.2, delay: 0.0, animations: {
                self.center.x += 20
                self.alpha = 1.0
            }, completion: nil)
        }
    }
}

/// ボタン  
class MyButton: UIButton {
    required init(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)!
    }
    override init(frame: CGRect) {
        super.init(frame: frame)
    }
    open func myInit(width:CGFloat) {
        self.frame.size = CGSize.init(width:width, height:width)
        self.layer.cornerRadius = width/2
        self.center = CGPoint(x:0, y:0)
        self.imageEdgeInsets = UIEdgeInsets(top:10, left:10, bottom:10, right:10)
    }
}

class RoundRectButton: MyButton {
    required init(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        self.myInit(width:50)
        self.backgroundColor = UIColor(red:0.0,green:0.0,blue:0.0,alpha:0.5)
    }
    override init(frame: CGRect) {
        super.init(frame: frame)
    }
    public var isSwitch:Bool = true
    public func setSwitch(b:Bool) {
        isSwitch = b
        if isSwitch == true {
            self.backgroundColor = UIColor(red:0.2,green:0.4,blue:0.8,alpha:1.0)
        } else {
            self.backgroundColor = UIColor(red:0.0,green:0.0,blue:0.0,alpha:0.5)
        }
    }
}

class CircleButton: MyButton {
    required init(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)

        self.myInit(width:60)
        self.backgroundColor = UIColor.clear
        self.layer.borderColor = UIColor(red:0.0,green:0.0,blue:0.0,alpha:0.5).cgColor
        self.layer.borderWidth = 8
    }
    override init(frame: CGRect) {
        super.init(frame: frame)
    }
}
/// セグメント
class MySegmentedControl: UISegmentedControl {
    required init(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)!
        self.tintColor = UIColor.white
        self.backgroundColor = UIColor(red:0.0,green:0.0,blue:0.0,alpha:0.3)
        
        self.frame.size = CGSize.init(width:220, height:30)  
        self.center = CGPoint(x:0, y:0)
    }
    override init(frame: CGRect) {
        super.init(frame: frame)
    }
}

extension UIDevice {
    // Return Cpu Cores
    var cpuCores: Int {
        var r = Int(self.getSysInfo(typeSpecifier:HW_NCPU))
        if (r==0) { r=1 }
        return r
    }
    func getSysInfo(typeSpecifier: Int32) -> Int {
        var size: size_t = MemoryLayout<Int>.size
        var results: Int = 0
        var mib: [Int32] = [CTL_HW, typeSpecifier]
        sysctl(&mib, 2, &results, &size, nil,0)
        return results
    }
}

final class ExampleRecorderDelegate: DefaultAVRecorderDelegate {
    static let `default` = ExampleRecorderDelegate()
    
    override func didFinishWriting(_ recorder: AVRecorder) {
        guard let writer: AVAssetWriter = recorder.writer else { return }
        PHPhotoLibrary.shared().performChanges({() -> Void in
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: writer.outputURL)
        }, completionHandler: { _, error -> Void in
            do {
                try FileManager.default.removeItem(at: writer.outputURL)
            } catch {
                print(error)
            }
        })
    }
}