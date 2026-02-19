//
//  ViewController.swift
//  navigation
//
//  Created by 殷雄 on 3/20/25.
//
//  AIzaSyDuq-bA6uuLX6oXoUFuKVRZlShHYhdBsFQ
import UIKit
import CoreLocation
import GoogleMaps

// 主视图控制器，包含GPS定位、指南针方向和地图导航功能
class ViewController: UIViewController {

    // 地图视图实例
    var mapView: GMSMapView!
    // Google Maps API Key
    // previous jacky's apiKey = "AIzaSyDuq-bA6uuLX6oXoUFuKVRZlShHYhdBsFQ"
    let apiKey = "AIzaSyAjtEhPZ8yCgx0gMgm15T8VskDJdTWH5bg"
    
    // 起点根据用户实时定位变，终点亦可变
    var origin = "Maple Hall, University of Washington, Seattle, WA"
    // var origin = "47.664639, -122.308286"
    var destination = "CSE Building, University of Washington, Seattle, WA"

    // 定位管理器，用于GPS和方向信息
    let locationManager = CLLocationManager()
    
    // Stage 4
    var routePoints: [Point] = []
    var threshold3Timer: Timer?
    
    // Stage 5 防止偶尔的一些outliers
    // 用于记录上一次触发路线重规划时的用户坐标
    var lastRecalculationCoordinate: CLLocationCoordinate2D?
    // GPS outlier 时仍然显示最近一次计算出的角度
    var lastValidAngle: Double?
    // BLE: store current phone heading angle and last send time
    var currentPhoneAngle: Double?
    var lastBLECommandSentAt: Date?
    // Store the last computed AdjustDirection and AngleDiff (for debugging/next steps)
    var lastAdjustDirection: UInt8?
    var lastAngleDiffOut: Double?
    // Track off-route state (outside thresholds 1 and 2)
    var isOffRoute: Bool = false
    
    // LiDAR debug grid (8×8) — temporary for verification
    var depthGridContainer: UIView!
    var depthGridLabels: [[UILabel]] = []
    
    // Stage 6 单位为米
    let threshold_1_radius = 20.0 // original = 4.0
    let threshold_2_width = 8.0 // original = 8.0
    let outlier_threshold_distance = 5.0 // original = 5.0
    
    // Stage 7
    // 在 ViewController 内新增搜索栏
    let searchBar: UISearchBar = {
        let sb = UISearchBar()
        sb.placeholder = "Please Enter Your Destination..."
        sb.translatesAutoresizingMaskIntoConstraints = false
        return sb
    }()
    
    // 显示用户当前位置的标签
    let locationLabel: UILabel = {
        let label = UILabel()
        label.text = "Current Locaiton：Obtaining in progress..."
        label.textAlignment = .center
        label.numberOfLines = 0
        label.backgroundColor = UIColor(white: 1, alpha: 0.8)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    // 显示用户设备朝向的标签
    let headingLabel: UILabel = {
        let label = UILabel()
        label.text = "Orientation of your Phone：Obtaining in progress..."
        label.textAlignment = .center
        label.backgroundColor = UIColor(white: 1, alpha: 0.8)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    // Stage 5
    // 显示期望用户朝向的标签
    let desiredDirectionLabel: UILabel = {
        let label = UILabel()
        label.text = "Expecting Orientation：Obtaining data in progress..."
        label.textAlignment = .center
        label.backgroundColor = UIColor(white: 1, alpha: 0.8)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    // Bottom UI labels to show AngleDiff and AdjustDirection
    let angleDiffLabel: UILabel = {
        let label = UILabel()
        label.text = "AngleDiff: --"
        label.textAlignment = .center
        label.numberOfLines = 1
        label.backgroundColor = UIColor(white: 1, alpha: 0.8)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    let adjustDirectionLabel: UILabel = {
        let label = UILabel()
        label.text = "AdjustDirection: --"
        label.textAlignment = .center
        label.numberOfLines = 1
        label.backgroundColor = UIColor(white: 1, alpha: 0.8)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()


    override func viewDidLoad() {
        super.viewDidLoad()

        setupMapView()
        setupLocationManager()
        setupLabels()
        requestRoute(origin, destination, threshold_1_radius, threshold_2_width)
        BLEManager.shared.start()
        setupDepthGridUI()
        LiDARManager.shared.start()
        LiDARManager.shared.onGridUpdate = { [weak self] grid in
            self?.updateDepthGridUI(grid)
        }
    }

    // 初始化并配置地图视图
    private func setupMapView() {
        GMSServices.provideAPIKey(apiKey)
        let camera = GMSCameraPosition(latitude: 47.6553, longitude: -122.3035, zoom: 15.0)
        let options = GMSMapViewOptions()
        options.camera = camera

        mapView = GMSMapView(options: options)
        mapView.frame = view.bounds
        view.addSubview(mapView)
    }

    // 配置定位管理器，并开始定位和方向监测
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()

        if CLLocationManager.headingAvailable() {
            locationManager.startUpdatingHeading()
        } else {
            headingLabel.text = "Current Device Doesn't Support Orientaion Feature" // 设备不支持方向功能
        }
    }

    // 添加并布局显示定位和方向信息的标签
    private func setupLabels() {
        // 添加搜索栏到视图中 Stage 7
        view.addSubview(searchBar)
        view.addSubview(locationLabel)
        view.addSubview(headingLabel)
        view.addSubview(desiredDirectionLabel)
        view.addSubview(angleDiffLabel)
        view.addSubview(adjustDirectionLabel)
        
        // 设置搜索栏代理
        searchBar.delegate = self

        NSLayoutConstraint.activate([
            // 搜索栏位于最顶部
            searchBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            
            // 位置标签位于搜索栏下方
            locationLabel.topAnchor.constraint(equalTo: searchBar.bottomAnchor, constant: 10),
            locationLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            locationLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            headingLabel.topAnchor.constraint(equalTo: locationLabel.bottomAnchor, constant: 10),
            headingLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            headingLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            
            desiredDirectionLabel.topAnchor.constraint(equalTo: headingLabel.bottomAnchor, constant: 10),
            desiredDirectionLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            desiredDirectionLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            
            // Bottom labels
            adjustDirectionLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -10),
            adjustDirectionLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            adjustDirectionLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            angleDiffLabel.bottomAnchor.constraint(equalTo: adjustDirectionLabel.topAnchor, constant: -8),
            angleDiffLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            angleDiffLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
        ])
    }

    // MARK: - LiDAR 8×8 Debug Grid UI (temporary)

    private func setupDepthGridUI() {
        let rows = LiDARManager.gridRows  // 16
        let cols = LiDARManager.gridCols  // 16
        let cellSize: CGFloat = 22
        let spacing: CGFloat = 1
        let gridW = CGFloat(cols) * cellSize + CGFloat(cols - 1) * spacing
        let gridH = CGFloat(rows) * cellSize + CGFloat(rows - 1) * spacing

        depthGridContainer = UIView()
        depthGridContainer.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        depthGridContainer.layer.cornerRadius = 8
        depthGridContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(depthGridContainer)

        NSLayoutConstraint.activate([
            depthGridContainer.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            depthGridContainer.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            depthGridContainer.widthAnchor.constraint(equalToConstant: gridW + 8),
            depthGridContainer.heightAnchor.constraint(equalToConstant: gridH + 8),
        ])

        depthGridLabels = []
        for r in 0..<rows {
            var rowLabels: [UILabel] = []
            for c in 0..<cols {
                let label = UILabel()
                label.text = "--"
                label.font = UIFont.monospacedSystemFont(ofSize: 7, weight: .medium)
                label.textAlignment = .center
                label.textColor = .white
                label.backgroundColor = UIColor.gray.withAlphaComponent(0.5)
                label.layer.cornerRadius = 2
                label.clipsToBounds = true
                label.translatesAutoresizingMaskIntoConstraints = false
                depthGridContainer.addSubview(label)

                let x = 4 + CGFloat(c) * (cellSize + spacing)
                let y = 4 + CGFloat(r) * (cellSize + spacing)
                NSLayoutConstraint.activate([
                    label.leadingAnchor.constraint(equalTo: depthGridContainer.leadingAnchor, constant: x),
                    label.topAnchor.constraint(equalTo: depthGridContainer.topAnchor, constant: y),
                    label.widthAnchor.constraint(equalToConstant: cellSize),
                    label.heightAnchor.constraint(equalToConstant: cellSize),
                ])
                rowLabels.append(label)
            }
            depthGridLabels.append(rowLabels)
        }
    }

    private func updateDepthGridUI(_ grid: [[Float]]) {
        let dangerClose = LiDARManager.shared.dangerCloseDistance  // 0.5m — red
        let danger      = LiDARManager.shared.dangerDistance       // 1.0m — orange
        let caution     = LiDARManager.shared.cautionDistance      // 2.0m — yellow

        for r in 0..<grid.count {
            for c in 0..<grid[r].count {
                guard r < depthGridLabels.count, c < depthGridLabels[r].count else { continue }
                let val = grid[r][c]
                let label = depthGridLabels[r][c]

                if val > 99 {
                    label.text = "inf"
                    label.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.6)
                } else {
                    label.text = String(format: "%.1f", val)
                    if val < dangerClose {
                        // Red: < 0.5m
                        label.backgroundColor = UIColor.systemRed.withAlphaComponent(0.8)
                    } else if val < danger {
                        // Orange: 0.5m – 1.0m
                        label.backgroundColor = UIColor.systemOrange.withAlphaComponent(0.7)
                    } else if val < caution {
                        // Yellow: 1.0m – 2.0m
                        label.backgroundColor = UIColor.systemYellow.withAlphaComponent(0.6)
                    } else {
                        // Green: > 2.0m
                        label.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.5)
                    }
                }
            }
        }
    }

    // Stage 4
    // 发起路线请求（使用GoogleMapsHelper处理）
    // 在ViewController.swift中修改此方法，路径绘制完成后保存路径点
    private func requestRoute(_ origin: String, _ destination: String, _ threshold_1_Radius: Double, _ threshold_2_Width: Double) {
        GoogleMapsHelper.shared.fetchDirections(
            origin: origin,
            destination: destination,
            apiKey: apiKey
        ) { [weak self] polyline in
            guard let polyline = polyline, let self = self else { return }
            DispatchQueue.main.async {
                self.routePoints = GoogleMapsHelper.shared.drawRouteOnMap(polyline: polyline, mapView: self.mapView, threshold_1_Radius: threshold_1_Radius, threshold_2_Width: threshold_2_Width)
            }
        }
    }
    
    // Stage 8 04/14/2025
    func formatAngle(_ angle: Double) -> String {
        return String(format: "%.2f", angle)
    }
}

// CLLocationManagerDelegate协议实现，负责位置和方向更新
extension ViewController: CLLocationManagerDelegate {

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let currentLocation = locations.last else { return }
        locationLabel.text = "Current Location：\nLatitude：\(currentLocation.coordinate.latitude)\nLongitude：\(currentLocation.coordinate.longitude)"
        // Stage 4
        checkUserThresholds(currentLocation.coordinate, outlier_threshold_distance)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let originalHeading = (newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading)
        var convertedAngle = (90 - originalHeading).truncatingRemainder(dividingBy: 360)
        if convertedAngle < 0 {
            convertedAngle += 360 }
        headingLabel.text = "Orientation of your Phone：\(convertedAngle)°"
        self.currentPhoneAngle = convertedAngle

        if !self.isOffRoute, let desired = self.lastValidAngle {
            self.applyAdjustDirectionLogic(desiredAngle: desired)
        } else if self.isOffRoute {
            // Keep UI showing off-route state
            self.updateAdjustUI(adjustDirection: 3, angleDiff: nil)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        locationLabel.text = "Location Update Failed：\(error.localizedDescription)"
    }
    
}

// Stage 4
// 实时位置阈值检测函数
extension ViewController {
    private func checkUserThresholds(_ userCoord: CLLocationCoordinate2D, _ outlier_threshold_distance: Double) {
        if routePoints.isEmpty {
            print("[THRESH] routePoints is empty; route not ready yet")
            self.updateAdjustUI(adjustDirection: nil, angleDiff: nil)
            return
        }

        var threshold1Indices: [Int] = []
        var threshold2Indices: [Int] = []

        for (index, point) in routePoints.enumerated() {
            let pointCoord = CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
            let distance = GoogleMapsHelper.shared.distanceInMeters(from: userCoord, to: pointCoord)
            
            // 阈值1（圆形区域）
            if distance <= threshold_1_radius {
                threshold1Indices.append(index)
            }
            
            // 阈值2（平行四边形区域）
            if index < routePoints.count - 1 {
                let nextPoint = routePoints[index + 1]
                let quad = GoogleMapsHelper.shared.createQuadrilateral(point1: point, point2: nextPoint, threshold_2_Width: threshold_2_width)
                if GoogleMapsHelper.shared.isPoint(userCoord, insideQuadrilateral: quad) {
                    threshold2Indices.append(index)
                }
            }
        }

        print("[THRESH] threshold1 count=\(threshold1Indices.count), threshold2 count=\(threshold2Indices.count)")

        // 若用户位于阈值1或阈值2内
        if !threshold1Indices.isEmpty || !threshold2Indices.isEmpty {
            self.isOffRoute = false
            let allIndices = threshold1Indices + threshold2Indices
            if let maxIndex = allIndices.max(), let angle = routePoints[maxIndex].angle {
                print("用户在阈值1或阈值2内，最大 index: \(maxIndex), angle: \(angle)")
                desiredDirectionLabel.text = "Expected Orientation：\(formatAngle(angle))°"
                lastValidAngle = (angle)  // 保存最新有效角度
                self.applyAdjustDirectionLogic(desiredAngle: angle)
            } else {
                desiredDirectionLabel.text = "Expected Orientation：Unknown"
                self.updateAdjustUI(adjustDirection: nil, angleDiff: nil)
            }
            resetThreshold3Timer()
        } else {
            // 用户处于阈值3内
            desiredDirectionLabel.text = "Recalculating Your Trip..."
            self.isOffRoute = true
            self.lastAdjustDirection = 3
            self.lastAngleDiffOut = nil
            self.updateAdjustUI(adjustDirection: 3, angleDiff: nil)

            // Optionally notify peripheral that we're off-route (direction=3, magnitude=0)
            let now = Date()
            if let last = lastBLECommandSentAt, now.timeIntervalSince(last) < 0.2 {
                // throttle to 5 Hz
            } else {
                let packet = Data([3, 0])
                BLEManager.shared.sendCommand(packet)
                lastBLECommandSentAt = now
            }

            if threshold3Timer == nil {
                if let lastCoord = lastRecalculationCoordinate {
                    let diff = GoogleMapsHelper.shared.distanceInMeters(from: userCoord, to: lastCoord)
                    if diff < outlier_threshold_distance {
                        // 若两次数据变化不明显，则视为异常数据，不重新规划路线
                        print("GPS outlier detected, \(diff) meter in difference, NOT Recalculating Route")
                        if let validAngle = lastValidAngle {
                            desiredDirectionLabel.text = "Expected Orientation：\(formatAngle(validAngle))° GPS outlier: \(diff) meter"
                        } else {
                            if let firstAngle = routePoints.first?.angle {
                                desiredDirectionLabel.text = "Expected Orientation：\(formatAngle(firstAngle))° GPS outlier: \(diff) meter"
                            } else {
                                desiredDirectionLabel.text = "Unable to Determine Route. Recalculating... GPS outlier: \(diff) meter"
                            }
                        }
                        return
                    }
                }
                // 更新 lastRecalculationCoordinate 并启动定时器进行重规划
                lastRecalculationCoordinate = userCoord
                threshold3Timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
                    guard let self = self else { return }
                    print("用户在阈值3，重新计算路径")
                    self.requestRoute("\(userCoord.latitude),\(userCoord.longitude)", self.destination, threshold_1_radius, threshold_2_width)
                    self.threshold3Timer = nil
                }
            }
        }
    }

    private func resetThreshold3Timer() {
        threshold3Timer?.invalidate()
        threshold3Timer = nil
    }
}

extension ViewController: UISearchBarDelegate {
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        // 获取用户输入内容
        guard let searchText = searchBar.text, !searchText.isEmpty else { return }
        
        // 更新目的地
        destination = searchText
        
        // 隐藏键盘
        searchBar.resignFirstResponder()
        
        // 可选：将当前位置作为起点（或保留之前的起点）
        if let currentLocation = locationManager.location {
            origin = "\(currentLocation.coordinate.latitude),\(currentLocation.coordinate.longitude)"
        }
        
        // 发起新的路线请求，使用当前的阈值设置
        requestRoute(origin, destination, threshold_1_radius, threshold_2_width)
    }
}
// MARK: - BLE / Haptics helpers
extension ViewController {
    // Apply requested AdjustDirection / AngleDiff rules and log the results.
    // AngleDiff is defined as: Orientation of your phone - Expected Orientation
    private func applyAdjustDirectionLogic(desiredAngle: Double) {
        guard let phoneAngle = currentPhoneAngle else { return }
        let rawAngleDiff = phoneAngle - desiredAngle

        var adjustDirection: UInt8 = 0 // 0: none, 1: left vibrate, 2: right vibrate
        var angleDiffOut = rawAngleDiff

        // Implement the exact branching provided:
        if rawAngleDiff > 5 && rawAngleDiff <= 180 {
            // Turn right
            adjustDirection = 2
            angleDiffOut = rawAngleDiff
        } else if rawAngleDiff > 5 && rawAngleDiff > 180 {
            // Turn left, use the complementary angle
            adjustDirection = 1
            angleDiffOut = 360 - rawAngleDiff
        } else if rawAngleDiff < -5 && rawAngleDiff <= -180 {
            // Turn right, wrap negative large angle
            adjustDirection = 2
            angleDiffOut = 360 + rawAngleDiff
        } else if rawAngleDiff < -5 && rawAngleDiff > -180 {
            // Turn left, wrap negative small angle
            adjustDirection = 1
            angleDiffOut = (-1 * rawAngleDiff)
        } else {
            // Within ±5 degrees: no vibration
            adjustDirection = 0
            angleDiffOut = rawAngleDiff
        }

        // Save for future use (e.g., sending over BLE next step)
        self.lastAdjustDirection = adjustDirection
        self.lastAngleDiffOut = angleDiffOut

        self.updateAdjustUI(adjustDirection: adjustDirection, angleDiff: angleDiffOut)

        // Send minimal 2-byte packet: [AdjustDirection, AngleDiffMagnitude]
        // Clamp AngleDiffMagnitude to 0...180 and round to nearest integer
        let magnitudeInt = max(0, min(180, Int(round(angleDiffOut))))
        let magnitude = UInt8(magnitudeInt)

        let now = Date()
        if let last = lastBLECommandSentAt, now.timeIntervalSince(last) < 0.2 {
            // throttle to 5 Hz
        } else {
            let packet = Data([adjustDirection, magnitude])
            BLEManager.shared.sendCommand(packet)
            lastBLECommandSentAt = now
        }

        // Log for debugging
        print("[ADJUST] phone=\(formatAngle(phoneAngle))°, desired=\(formatAngle(desiredAngle))°")
        print("[ADJUST] raw AngleDiff (phone - desired) = \(formatAngle(rawAngleDiff))°")
        print("[ADJUST] AdjustDirection = \(adjustDirection) (0:none, 1:left, 2:right), AngleDiff(out) = \(formatAngle(angleDiffOut))°")
    }
    
    // Update bottom UI labels for AngleDiff and AdjustDirection
    private func updateAdjustUI(adjustDirection: UInt8?, angleDiff: Double?) {
        // AdjustDirection mapping
        if let dir = adjustDirection {
            let dirText: String
            switch dir {
            case 1: dirText = "Left (1)"
            case 2: dirText = "Right (2)"
            case 3: dirText = "Off-route (3)"
            default: dirText = "None (0)"
            }
            adjustDirectionLabel.text = "AdjustDirection: \(dirText)"
        } else {
            adjustDirectionLabel.text = "AdjustDirection: N/A"
        }

        if let diff = angleDiff {
            angleDiffLabel.text = "AngleDiff: \(formatAngle(diff))°"
        } else {
            angleDiffLabel.text = "AngleDiff: N/A"
        }
    }
}

