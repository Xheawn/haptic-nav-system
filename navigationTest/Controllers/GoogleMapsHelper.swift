//
//  GoogleMapsHelper.swift
//  navigation
//
//  Created by 殷雄 on 3/26/25.
//

import UIKit
import GoogleMaps

/// Google Maps 辅助类（处理路线获取和地图绘制功能）
class GoogleMapsHelper {

    /// 单例模式（确保全局唯一实例）
    static let shared = GoogleMapsHelper()

    private init() {} // 私有化构造方法

    /// 通过Google Directions API获取路径数据
    /// - Parameters:
    ///   - origin: 起点地址
    ///   - destination: 终点地址
    ///   - apiKey: Google Maps API 密钥
    ///   - completion: 完成时的回调，返回polyline字符串
    func fetchDirections(origin: String, destination: String, apiKey: String, completion: @escaping (String?) -> Void) {
        let originEncoded = origin.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        let destinationEncoded = destination.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        let directionsURL = "https://maps.googleapis.com/maps/api/directions/json?origin=\(originEncoded)&destination=\(destinationEncoded)&mode=walking&key=\(apiKey)"

        URLSession.shared.dataTask(with: URL(string: directionsURL)!) { (data, response, error) in
            guard let data = data, error == nil else {
                print("请求失败：", error ?? "")
                completion(nil)
                return
            }

            do {
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                   let routes = json["routes"] as? [[String: Any]],
                   let route = routes.first,
                   let overviewPolyline = route["overview_polyline"] as? [String: Any],
                   let points = overviewPolyline["points"] as? String {
                    completion(points)
                } else {
                    print("未找到有效路线数据")
                    completion(nil)
                }
            } catch {
                print("JSON解析失败：", error)
                completion(nil)
            }
        }.resume()
    }

    /// 在地图上绘制路径并创建带有角度信息的坐标点
    /// - Parameters:
    ///   - polyline: Google Directions API返回的编码后的路径信息
    ///   - mapView: 需要绘制路径的地图视图
    func drawRouteOnMap(polyline: String, mapView: GMSMapView, threshold_1_Radius: Double, threshold_2_Width: Double) -> [Point] {
        guard let path = GMSPath(fromEncodedPath: polyline) else {
            print("路径解析失败")
            return []
        }

        // 清空地图上原有的绘制
        mapView.clear()

        // 绘制路径线
        let routeLine = GMSPolyline(path: path)
        routeLine.strokeWidth = 5.0
        routeLine.strokeColor = .systemBlue
        routeLine.map = mapView

        // 自动调整地图视图范围
        let bounds = GMSCoordinateBounds(path: path)
        let update = GMSCameraUpdate.fit(bounds, withPadding: 50)
        mapView.animate(with: update)

        // 存储路径点
        var points: [Point] = []

        for index in 0..<Int(path.count()) {
            let coordinate = path.coordinate(at: UInt(index))
            let point = Point(index: index, latitude: coordinate.latitude, longitude: coordinate.longitude)

            // 计算指向下一个点的角度
            if index < Int(path.count()) - 1 {
                let nextCoordinate = path.coordinate(at: UInt(index + 1))
                let angle = calculateAngle(from: coordinate, to: nextCoordinate)
                point.setAngle(angle)

                // 阈值2 (黄色平行四边形区域绘制)
                drawThreshold2(from: coordinate, to: nextCoordinate, mapView: mapView, threshold_2_Width: threshold_2_Width)
            } else {
                point.setAngle(nil)
            }

            points.append(point)

            // 阈值1（绿色圆圈区域绘制）
            let threshold1Circle = GMSCircle(position: coordinate, radius: threshold_1_Radius)
            threshold1Circle.strokeColor = UIColor.green.withAlphaComponent(0.8)
            threshold1Circle.strokeWidth = 2
            threshold1Circle.fillColor = UIColor.green.withAlphaComponent(0.3)
            threshold1Circle.map = mapView

            // 打印点的信息
            print(point)
        }
        return points
    }
    
    // 根据距离和方位角计算新坐标
    // 绘制阈值2的平行四边形区域
    private func coordinate(from coord: CLLocationCoordinate2D, distanceMeters: Double, bearingDegrees: Double) -> CLLocationCoordinate2D {
        let earthRadius = 6378137.0
        let bearingRad = bearingDegrees * .pi / 180.0
        let lat1 = coord.latitude * .pi / 180.0
        let lon1 = coord.longitude * .pi / 180.0

        let lat2 = asin(sin(lat1) * cos(distanceMeters / earthRadius) +
                        cos(lat1) * sin(distanceMeters / earthRadius) * cos(bearingRad))
        let lon2 = lon1 + atan2(sin(bearingRad) * sin(distanceMeters / earthRadius) * cos(lat1),
                                cos(distanceMeters / earthRadius) - sin(lat1) * sin(lat2))

        return CLLocationCoordinate2D(latitude: lat2 * 180.0 / .pi, longitude: lon2 * 180.0 / .pi)
    }

    // 使用CoreLocation实现精确绘制阈值2（黄色平行四边形区域），不再依赖GoogleMapsUtils
    private func drawThreshold2(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D, mapView: GMSMapView, threshold_2_Width: Double) {
        let halfWidth = threshold_2_Width / 2 // 平行四边形半宽 (总宽度4米)
        
        // 使用CoreLocation准确计算方位角
        let deltaLong = end.longitude - start.longitude
        let y = sin(deltaLong * .pi / 180) * cos(end.latitude * .pi / 180)
        let x = cos(start.latitude * .pi / 180) * sin(end.latitude * .pi / 180) -
                sin(start.latitude * .pi / 180) * cos(end.latitude * .pi / 180) * cos(deltaLong * .pi / 180)
        let bearingRad = atan2(y, x)
        let bearingDegrees = (bearingRad * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
        
        let perpendicularBearing1 = bearingDegrees + 90
        let perpendicularBearing2 = bearingDegrees - 90
        
        // 起点左右两侧坐标
        let startLeft = coordinate(from: start, distanceMeters: halfWidth, bearingDegrees: perpendicularBearing1)
        let startRight = coordinate(from: start, distanceMeters: halfWidth, bearingDegrees: perpendicularBearing2)
        
        // 终点左右两侧坐标
        let endLeft = coordinate(from: end, distanceMeters: halfWidth, bearingDegrees: perpendicularBearing1)
        let endRight = coordinate(from: end, distanceMeters: halfWidth, bearingDegrees: perpendicularBearing2)
        
        // 构造路径绘制平行四边形
        let path = GMSMutablePath()
        path.add(startLeft)
        path.add(endLeft)
        path.add(endRight)
        path.add(startRight)
        
        let polygon = GMSPolygon(path: path)
        polygon.strokeColor = UIColor.yellow.withAlphaComponent(0.8)
        polygon.strokeWidth = 2
        polygon.fillColor = UIColor.yellow.withAlphaComponent(0.3)
        polygon.map = mapView
    }
    
    // Stage 4
    

    /// 计算两个坐标之间的角度，以正X轴为0°，逆时针为正
    /// - Parameters:
    ///   - start: 起始点经纬度
    ///   - end: 终点经纬度
    /// - Returns: 角度值（单位：度）
    private func calculateAngle(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D) -> Double {
        let deltaX = end.longitude - start.longitude
        let deltaY = end.latitude - start.latitude
        let radians = atan2(deltaY, deltaX)
        var degrees = radians * (180.0 / .pi)

        // 标准化角度到0-360°
        if degrees < 0 {
            degrees += 360
        }

        return degrees
    }
}

// Stage 4
// MARK: - 辅助函数扩展 (阈值检测用)

extension GoogleMapsHelper {
    
    /// 计算两个坐标之间的实际距离（米）
    func distanceInMeters(from coord1: CLLocationCoordinate2D, to coord2: CLLocationCoordinate2D) -> Double {
        let location1 = CLLocation(latitude: coord1.latitude, longitude: coord1.longitude)
        let location2 = CLLocation(latitude: coord2.latitude, longitude: coord2.longitude)
        return location1.distance(from: location2)
    }

    /// 构建两个路径点之间的平行四边形区域（用于阈值2检测）
    func createQuadrilateral(point1: Point, point2: Point, threshold_2_Width: Double) -> [CLLocationCoordinate2D] {
        let halfWidth = threshold_2_Width / 2 // 半宽，平行四边形总宽为4米
        let perpendicularBearing = (point1.angle ?? 0) + 90.0

        let coord1 = CLLocationCoordinate2D(latitude: point1.latitude, longitude: point1.longitude)
        let coord2 = CLLocationCoordinate2D(latitude: point2.latitude, longitude: point2.longitude)

        // 点1两侧坐标
        let point1Left = coordinate(from: coord1, distanceMeters: halfWidth, bearingDegrees: perpendicularBearing)
        let point1Right = coordinate(from: coord1, distanceMeters: halfWidth, bearingDegrees: perpendicularBearing - 180)

        // 点2两侧坐标
        let point2Left = coordinate(from: coord2, distanceMeters: halfWidth, bearingDegrees: perpendicularBearing)
        let point2Right = coordinate(from: coord2, distanceMeters: halfWidth, bearingDegrees: perpendicularBearing - 180)

        return [point1Left, point2Left, point2Right, point1Right]
    }

    /// 判断一个坐标点是否在给定的四边形区域内（用于阈值2检测）
    func isPoint(_ point: CLLocationCoordinate2D, insideQuadrilateral quad: [CLLocationCoordinate2D]) -> Bool {
        guard quad.count == 4 else { return false }

        let A = quad[0], B = quad[1], C = quad[2], D = quad[3]

        func cross(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D, _ c: CLLocationCoordinate2D) -> Double {
            return (b.longitude - a.longitude) * (c.latitude - a.latitude) -
                   (b.latitude - a.latitude) * (c.longitude - a.longitude)
        }

        let cross1 = cross(A, B, point)
        let cross2 = cross(B, C, point)
        let cross3 = cross(C, D, point)
        let cross4 = cross(D, A, point)

        // 所有叉积同号，则点在平行四边形内
        return (cross1 >= 0 && cross2 >= 0 && cross3 >= 0 && cross4 >= 0) ||
               (cross1 <= 0 && cross2 <= 0 && cross3 <= 0 && cross4 <= 0)
    }
}
