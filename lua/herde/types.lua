---@class HerdeWorkspace
---@field id string Namespaced opaque identity
---@field name string
---@field path? string
---@field remote? boolean
---@field project_id? string Shared repository identity for linked worktrees
---@field project_name? string
---@field project_path? string Repository root, distinct from checkout path

---@class HerdeAgent
---@field id string Occupant identity, not pane position
---@field workspace_id string
---@field pane_id string Backend pane handle
---@field name string
---@field kind string
---@field state 'idle'|'working'|'blocked'|'done'|'unknown'
---@field path? string
---@field remote? boolean
---@field identity_stable? boolean False means labels cannot be safely restored after restart

---@class HerdeSnapshot
---@field namespace string
---@field workspaces HerdeWorkspace[]
---@field agents HerdeAgent[]

---@class HerdeBackend
---@field capabilities table<string, boolean>
---@field snapshot fun(self:HerdeBackend, cb:fun(err:any, snapshot:HerdeSnapshot?))
---@field read fun(self:HerdeBackend, agent:HerdeAgent, cb:fun(err:any, text:string?))
---@field focus fun(self:HerdeBackend, agent:HerdeAgent, cb:fun(err:any, result:any))
---@field prompt fun(self:HerdeBackend, agent:HerdeAgent, text:string, cb:fun(err:any, result:any))
---@field stop fun(self:HerdeBackend)
return {}
