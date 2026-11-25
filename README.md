# -15-

OnePlus 15 (PLK110 / Android 17) 全局低延迟模块。

功能包括触控固件表补丁、Wi-Fi 驱动省电关闭、王者荣耀 DSCP EF 标记以及 WALT/cpufreq 升频加速。模块会自动备份原厂触控 XML 和 Wi-Fi 配置，卸载时回滚。

## 文件

- `一加15_lowlat-v1.0.0.zip`：可直接通过 KernelSU、Magisk 或 APatch 刷入的模块包
- `module.prop`、`core.sh`、`customize.sh` 等：模块源文件

## 安装

在 root 管理器中刷入 `一加15_lowlat-v1.0.0.zip`，然后重启设备。

仅适用于 OnePlus 15 (PLK110)，其他机型请谨慎使用。不要与 `touchzero`、`tp_photon` 或 `tp_fast` 同时安装。
