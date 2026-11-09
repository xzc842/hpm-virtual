本项目是一个虚拟仿真环境,主程序是godot，软件启动时，欢迎界面让用户打开一个项目，打开项目后进入仿真界面
检查项目根目录的virtual文件夹，如果没有，就让用户打开blender创建虚拟环境

virtual文件夹里有virtual.glb,需要加载这个，然后加载virtual.json,把摩擦系数绑定到面，并从里边获得各个设备对应的是哪部份的模型
设备包的目录是用户家目录/.hpm/packages,所有设备都需要在每个包的debug文件夹获得virtual.gd,这是一个用于仿真该设备的脚本

需要一个bledner插件，能打开项目文件夹，加载该项目设备的，对应的包，从包的debug目录读取device.gltf，device.json，在界面上展示，用户可以直接拖拽模型到3d场景，保存时生成virtual.glb、virtual.json

需要编写virtual.json\device.json、virtual.gd规范，描述怎么保存各个虚拟设备的信息，外部gd脚本怎么和主程序交互
在docs/目录下是如何连接到调试器中控程序的说明
