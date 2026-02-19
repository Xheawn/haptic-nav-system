class Point:
    def __init__(self, index: int, latitude: float, longitude: float, angle: float = None):
        self.index = index
        self.latitude = latitude
        self.longitude = longitude
        self.angle = angle  # Ensure angle is always defined

    def set_angle(self, angle: float):
        self.angle = angle

    def __repr__(self) -> str:
        point_to_str = f"latitude: {self.latitude}\nlongitude: {self.longitude}\n"
        if self.angle is not None:
            point_to_str += f"angle: {self.angle}\n\n"
        return point_to_str
        
