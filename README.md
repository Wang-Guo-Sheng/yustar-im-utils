## Rime 撤消上屏
一键删除整词，然后重新选词
模式一：按快捷键后删除整词，重新弹出输入框
模式二：删除后再按一次，自动上屏下一个候选


用`rime-lua-sendKeyCode-main`下用两个makefile分别编译一次，把生成的两个dll放在合适位置，dll目录粘贴到`cycle_select.lua`中
把脚本放在rime用户文件夹下的lua文件夹中，然后参考 `yustar_sc.schema.yaml`在方案schema中添加相应配置
