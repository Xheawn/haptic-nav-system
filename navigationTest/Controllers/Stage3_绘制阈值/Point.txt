//
//  Points.swift
//  navigation
//
//  Created by 殷雄 on 3/20/25.
//
import Foundation

/// 表示路径上的一个坐标点
class Point: CustomStringConvertible {
    
    /// 点在路径中的索引位置
    var index: Int
    
    /// 点的纬度
    var latitude: Double
    
    /// 点的经度
    var longitude: Double
    
    /// 当前点指向下一个点的角度（以正X轴为0°），最后一个点为nil
    var angle: Double?

    /// 初始化方法
    /// - Parameters:
    ///   - index: 点在路径中的索引
    ///   - latitude: 纬度坐标
    ///   - longitude: 经度坐标
    ///   - angle: 到下个点的方向角度（可选）
    init(index: Int, latitude: Double, longitude: Double, angle: Double? = nil) {
        self.index = index
        self.latitude = latitude
        self.longitude = longitude
        self.angle = angle
    }

    /// 设置指向下一个点的角度
    /// - Parameter angle: 角度值（以度为单位），可为nil
    func setAngle(_ angle: Double?) {
        self.angle = angle
    }

    /// 便于调试和打印
    var description: String {
        var pointToStr = "Index: \(index)\n(latitude,longitude): \(latitude) \(longitude)\n"
        if let angle = angle {
            pointToStr += "angle: \(angle)°\n"
        } else {
            pointToStr += "angle: nil\n"
        }
        return pointToStr
    }
}
