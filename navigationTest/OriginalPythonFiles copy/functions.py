from enum import Enum
import time
import googlemaps
import polyline
import math
from typing import List, Optional, Tuple, Union
import GPS
from Point import Point
import datetime

class ThresholdStatus(Enum):
    THRESHOLD_CIRCLE = 1   # 在圆形阈值里面
    THRESHOLD_RECTANGLE = 2  # 在圆形阈值外,但在长方形阈值里面
    ABOVE_THRESHOLD = 3   # 高于阈值

class TurningDirection(Enum):
    CLOCKWISE = 1   # 顺时针
    COUNTERCLOCKWISE = 2  # 逆时针

def generate_path(api_authorization: googlemaps.Client, origin: Union[Tuple[float, float], str], destination: Union[Tuple[float, float], str]) -> List[Point]:
    """
    根据当前和终点坐标/地点(字符串格式)生成路径。

    参数:
        api_authorization: 当前API认证。 例子: api_authorization = googlemaps.Client(key='你的googlemaps API')。
        origin: 起点,可为坐标或字符串形式。
        destination:终点,可为坐标或字符串形式。

    返回值:
        points:google maps 生成的这条路径上的点。
    """
    points: List[Point] = []

    # 获取路线的详细信息
    directions_result = api_authorization.directions(
        origin,
        destination,
        mode="walking",      # 可改为 "walking", "bicycling", "transit" 等模式
        departure_time="now" # 指定出发时间
    )

    # 提取 overview_polyline 中的编码字符串
    encoded_poly = directions_result[0]['overview_polyline']['points']

    # 解码为经纬度坐标列表
    coords = polyline.decode(encoded_poly)

    # 计算每2个坐标之间与x轴(纬线)所夹的角度
    # 我们假设x轴正方向为0度,逆时针为正,我们想要输出0到360度的区间,所以我们对不同的象限(方向)分类讨论
    for i in range(1, len(coords)):
        la_diff = coords[i][0] - coords[i - 1][0]
        long_diff = coords[i][1] - coords[i - 1][1]
        if (long_diff >= 0):
            if (la_diff >= 0): # 第一象限
                angle_degree = math.degrees(math.atan2(la_diff, long_diff))
            else: # 第四象限
                angle_degree = math.degrees(math.atan2(la_diff, long_diff)) + 360.0
        else: # 第二象限/第三象限
            angle_degree = math.degrees(math.atan2(la_diff, long_diff)) + 180.0
        
        points.append(Point(i - 1, coords[i - 1][0], coords[i - 1][1], angle_degree))

    # 导入最后一个点。因为最后一个点没有方向,我们把他设为none,也就是不传任何值。
    points.append(Point(len(coords) - 1, coords[len(coords) - 1][0], coords[len(coords) - 1][1]))


    return points


def fix_angle(curr_location: Point, points: List[Point], radius: float) -> Union[Tuple[TurningDirection, float], str]:
    """
    判断当前的点在哪个阈值以内。

    异常:
        假设curr_location的没有angle属性则raise ValueError。

    参数:
        curr_location: 人物当前所在位置及面向的方向。
        points: google maps预测的线路上的所有点。
        radius:我们设的半径阈值,会是一个常数。

    返回值:
        Tuple[TurningDirection, float] / "用户离规划路径太远了,请重新规划路径" / "已到达终点"
        需要修正的角度(0到180度),以及是顺时针还是逆时针。
        假设我们需要比较的点没有angle属性,则我们认为用户到达了终点(因为最后一个点没有angle属性),所以会return字符串 “已到达终点”。
        假设curr_location在阈值外面则返回字符串“用户离规划路径太远了,请重新规划路径”
    """
    if curr_location.angle is None:
        raise ValueError(f"{curr_location} 里没有角度")
    if _is_in_threshold(curr_location, points, radius) == ThresholdStatus.ABOVE_THRESHOLD:
        return "用户离规划路径太远了,请重新规划路径"
    point_1 = _find_nearest_two_points(curr_location, points)[0]
    point_2 = _find_nearest_two_points(curr_location, points)[1]

    nearest_point_angle = point_1.angle
    previous_angle = point_1.angle if point_1.index < point_2.index else point_2.angle

    turning_angle: float

    if _is_in_threshold(curr_location, points, radius) == ThresholdStatus.THRESHOLD_CIRCLE:
        if nearest_point_angle is not None : turning_angle = curr_location.angle - nearest_point_angle
    if _is_in_threshold(curr_location, points, radius) == ThresholdStatus.THRESHOLD_RECTANGLE:
        if previous_angle is not None : turning_angle =  curr_location.angle - previous_angle

    if turning_angle is None:
        return "已到达终点"
    
    if (-360 <= turning_angle <= -180):
        return TurningDirection.CLOCKWISE, 360.0 + turning_angle
    if (-180 < turning_angle <= 0):
        return TurningDirection.COUNTERCLOCKWISE, -turning_angle
    if (0 < turning_angle <= 180):
        return TurningDirection.CLOCKWISE, turning_angle
    if (180 < turning_angle <= 360):
        return TurningDirection.COUNTERCLOCKWISE, 360.0 - turning_angle


def _is_in_threshold(curr_location: Point, points: List[Point], radius: float) -> ThresholdStatus:
    """
    判断当前的点在哪个阈值以内。

    参数:
        curr_location: 人物当前所在位置及面向的方向。
        points: google maps预测的线路上的所有点。
        radius:我们设的半径阈值,会是一个常数。

    返回值:
        ThresholdStatus枚举类3个值的其中一个。
    """
    nearest_point, second_nearest_point = _find_nearest_two_points(curr_location, points)
    if _distance(curr_location, nearest_point) <= radius:
        return ThresholdStatus.THRESHOLD_CIRCLE
    if _is_point_in_parallelogram(curr_location, List[Tuple[nearest_point.longitude, nearest_point.latitude + radius], 
                                                     Tuple[nearest_point.longitude, nearest_point.latitude - radius],
                                                     Tuple[second_nearest_point.longitude, nearest_point.latitude - radius],
                                                     Tuple[second_nearest_point.longitude, nearest_point.latitude + radius]]):
        return ThresholdStatus.THRESHOLD_RECTANGLE
    return ThresholdStatus.THRESHOLD_RECTANGLE
    
def _find_nearest_two_points(curr_location: Point, points: List[Point]) -> Tuple[Point, Point]:
    """
    寻找离当前坐标最近的2个点。

    参数:
        curr_location: 人物当前所在位置及面向的方向。
        points: google maps预测的线路上的所有点。

    返回值:
        一个Tuple。Tuple的第一个值是离curr_location最近的点,第二个值是离curr_location第二近的点。
    """
    if len(points) < 2:
        raise ValueError("输入点的数量至少为2个")

    # 计算所有点到curr_location的距离,并排序
    sorted_points = sorted(points, key=lambda point: _distance(curr_location, point))

    # 返回最近的两个点
    return sorted_points[0], sorted_points[1]

def _distance(p1: Point, p2: Point) -> float:
    """计算两个点之间的欧氏距离"""
    return math.hypot(p1.latitude - p2.latitude, p1.longitude - p2.longitude)

def _is_point_in_parallelogram(p: Point, vertices: List[Tuple[float, float]]) -> bool:
    """
    判断一个点是否在一个平行四边形/长方形里面。

    传入vertices的时候注意vertices必须是按照顺时针/逆时针的顺序放在List里面的

    原理是:判断平行四边形4向量与目标向量的叉乘的方向,假设方向一致,说明该点在平行四边形里面

    参数:p: 点坐标,(px, py)
        vertices: 平行四边形的顶点,顺时针或逆时针[(ax, ay), (bx, by), (cx, cy), (dx, dy)]
    """
    if len(vertices) != 4:
        raise ValueError("长方形有且只有4个顶点")
    px, py = p.longitude, p.latitude
    signs = []
    
    for i in range(4):
        ax, ay = vertices[i]
        bx, by = vertices[(i+1)%4]
        
        cross_product = _cross(bx - ax, by - ay, px - ax, py - ay)
        signs.append(cross_product)
    
    all_positive = all(s >= 0 for s in signs)
    all_negative = all(s <= 0 for s in signs)

    return all_positive or all_negative

def _cross(ax, ay, bx, by) -> float:
    """计算叉积"""
    return ax * by - ay * bx

    
    
