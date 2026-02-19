import time
import googlemaps
import polyline
import math
from typing import List
import GPS
from Point import Point
import datetime
import functions as fc

# 我们如果要调取实时方向就只能用swift获取ios的信息,我查了半天用windows基本不可能写swift,剩下的就靠你了加油
RADIUS = 2.0
points: List[Point] = []

# 请用你的 API Key 替换下面的 YOUR_API_KEY
gmaps = googlemaps.Client(key='AIzaSyDuq-bA6uuLX6oXoUFuKVRZlShHYhdBsFQ')
icloud_data = GPS.login("AppleID", "Password")

# 定义起点和终点地址(假设 UW 的 Maple Hall 和 UW 的 CSE Building 在 Seattle 校区)
origin = "Maple Hall, University of Washington, Seattle, WA"
destination = "CSE Building, University of Washington, Seattle, WA"

# 获取路线的详细信息
points = fc.generate_path(gmaps, origin, destination)

print(points)

# 打出目前所在的经纬度
with open("points_data.txt", "a", encoding="utf-8") as file:
    current_time = datetime.datetime.now()
    file.write(f"程序启动时间: {current_time.strftime('%Y-%m-%d %H:%M:%S')}\n")
    while True:
        # 获取当前的位置数据
        curr_location = GPS.get_curr_location(icloud_data)
        instruction = fc.fix_angle(curr_location, points, RADIUS)
        file.write(str(curr_location) + "\n")
        file.flush()  # 确保数据及时写入磁盘
        print(curr_location)
        print(instruction)
        if (instruction == "用户离规划路径太远了,请重新规划路径"):
            file.write("用户离规划路径太远了,请重新规划路径" + "\n")
            points = fc.generate_path(gmaps, curr_location, destination)
            continue
        if (instruction == "已到达终点"):
            print("用户已到达终点")
            file.write("用户已到达终点" + "\n")
            break
        time.sleep(5)



