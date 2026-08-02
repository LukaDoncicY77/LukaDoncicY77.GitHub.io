# Hexo 博客本地版本与受控发布流程

## 两层仓库边界

1. `G:\Y77\Blog` 是 Hexo 源文件的本地 Git 仓库，分支为 `source`。它保存文章源稿、已批准媒体、主题、配置和发布脚本，目前不连接远程源码仓库。
2. `LukaDoncicY77/LukaDoncicY77.GitHub.io` 的 `main` 分支是公开的 GitHub Pages 仓库，只接收 Hexo 生成后的静态网站。

`node_modules`、`public`、`.deploy_git`、Hexo 缓存、凭据、私人草稿和社交平台原始归档不纳入源文件 Git 仓库。

## 日常工作流程

1. 在 `source` 中编辑已通过隐私审核的文章和媒体。
2. 检查本地修改：

   ```powershell
   git status --short
   ```

3. 只做本地预检和构建，不上传：

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\prepare-deploy.ps1
   ```

4. 本地预览和隐私审核通过后，提交 Hexo 源文件：

   ```powershell
   git add -A
   git commit -m "Describe the approved blog update"
   ```

5. 只有用户明确同意上传当前版本后，才执行：

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\deploy-approved.ps1 -Approve
   ```

发布脚本会再次构建网站，并检查本地 Git 工作区、GitHub CLI 登录、远程 `main` 分支、大文件与禁止的私有目录名。没有 `-Approve` 参数时必须拒绝发布。

发布固定使用已经验证的 GitHub API 通道，只比较并上传 `public` 中与远端不同的生成文件，并以非强制方式推进 `main`。这样不会调用 Hexo 部署插件内部的强制推送。单个发生变化且超过 25 MiB 的文件会停止发布，需要另行使用安全的 Git 传输流程处理。

## GitHub 认证检查

GitHub CLI 位于：

```text
G:\Y77\.tools\gh-2.97.0\bin\gh.exe
```

检查登录：

```powershell
& 'G:\Y77\.tools\gh-2.97.0\bin\gh.exe' auth status
```

如果未登录：

```powershell
& 'G:\Y77\.tools\gh-2.97.0\bin\gh.exe' auth login -h github.com -p https -w
& 'G:\Y77\.tools\gh-2.97.0\bin\gh.exe' auth setup-git
```

## 故障边界

- 不使用社交平台原始归档作为 Hexo `source` 目录。
- 不在未提交的 Git 工作区上发布。
- 不用源文件覆盖公开仓库 `main`；只让 Hexo 部署器推送生成结果。
- 当 npm 缓存权限异常时，直接使用上述 PowerShell 脚本；脚本调用项目内的 `node_modules\.bin\hexo.cmd`，不依赖 npm 缓存写入。
