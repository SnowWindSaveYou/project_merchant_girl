# Git LFS 资源拉取说明

## 问题现象

项目中的图片（`.png`、`.jpg`）和音频（`.ogg`）文件全部由 Git LFS 管理，但 clone 仓库后这些文件可能只是 **LFS 指针文件**（约 130 字节的文本），而非真实的二进制数据。

指针文件内容示例：
```
version https://git-lfs.github.com/spec/v1
oid sha256:6dc48c6518...
size 1430047
```

此时构建工具无法识别这些文件为有效资源，会直接跳过，导致打包产物中缺失所有美术和音频资源。

## 影响范围

根据 `.gitattributes` 配置，以下格式均由 LFS 管理：

| 类型 | 格式 |
|------|------|
| 图片 | `*.png` `*.jpg` `*.jpeg` `*.bmp` `*.gif` `*.psd` |
| 音频 | `*.ogg` `*.wav` `*.mp3` |
| 视频 | `*.mp4` `*.mov` `*.avi` |

当前项目共 **187 个资源文件**（161 张图片 + 26 个音频）受此影响。

## 解决方法

clone 仓库后，在项目根目录执行：

```bash
git lfs install
git lfs pull
```

验证是否拉取成功：

```bash
# 检查文件大小，真实 PNG 通常远大于 130 字节
wc -c assets/image/bg_bell_tower_20260408143735.png
# 预期输出: 1430047（约 1.4MB）

# 检查文件头，应该是 PNG 二进制头而非文本
od -A x -t x1z -N 8 assets/image/bg_bell_tower_20260408143735.png
# 预期输出: 89 50 4e 47 0d 0a 1a 0a  >.PNG....<
```

## 常见问题

### Q: 为什么 clone 后 LFS 文件没有自动下载？

可能原因：
1. 本地未执行 `git lfs install`（需要每台机器初始化一次）
2. CI/CD 环境默认不拉取 LFS 文件（需在流程中显式添加 `git lfs pull`）
3. 网络代理未配置，LFS 服务器不可达

### Q: 如何确认文件是指针还是真实数据？

```bash
# 方法 1：查看文件首行
head -1 assets/image/xxx.png
# 指针文件会显示: version https://git-lfs.github.com/spec/v1
# 真实文件会显示: 乱码（二进制数据）

# 方法 2：用 git lfs 检查状态
git lfs status
```

### Q: 只想拉取部分文件？

```bash
# 只拉取 image 目录
git lfs pull --include="assets/image/**"

# 只拉取 png 文件
git lfs pull --include="*.png"
```
