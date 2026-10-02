# 可信任务卡

由主对话批准并提交，不由任务分支自授权限。通常从 main 读取；BaseBranch 决定差异基线，PolicyRef 决定已批准卡的来源，默认 PolicyRef=BaseBranch。首次 team-workflow 的 main 尚无卡，总控记录一个固定策略提交；只能对本次授权范围使用，不能把任意当前分支当成通用可信策略。

每卡包含 TaskId、Owner、Role、AllowedPaths、RequiredChecks、Checks。AllowedPaths 只允许精确仓库相对路径或以 / 结尾的目录前缀，不使用通配符、绝对路径、.. 或重复分隔符。Role=worker 仍受主对话专属文件保护，Role=coordinator 只用于主对话明确批准的治理任务。

每个检查含 Id、Executable、Arguments 数组、ExpectedExitCode、EvidencePaths。参数不拼接成 shell 命令；命令在可信任务卡中批准。Missing tool / 没有执行 / 错误退出 / 证据缺失不能写通过。

ManualAcceptance 是供总控和人逐项复核的要求，不会被脚本自动认证。env-bringup 即使 delivery-files 通过也仍须实际接线、显示与稳定性证据。任务日志、PR模板和报告共同表达验证层级。

新任务先由主对话通过 PR 增加或批准任务卡和日志，合入 main 后才启动普通任务分支。自己的卡出现在分支里不表示获准使用。
