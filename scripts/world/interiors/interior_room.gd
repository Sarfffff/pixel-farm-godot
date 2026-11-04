extends Node2D
## 室内场景根节点：只负责声明"这间屋子的相机边界"。
##
## 住宅与店铺尺寸不同，HouseManager 不再写死一套 `interior_bounds`，
## 而是进屋时读这个属性；缺失时回退到它自己的默认值。

@export var camera_bounds: Rect2 = Rect2(0, 0, 432, 352)
