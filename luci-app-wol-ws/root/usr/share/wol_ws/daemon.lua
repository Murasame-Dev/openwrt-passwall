local socket = require("socket")
local uci = require("luci.model.uci").cursor()
local json = require("luci.jsonc")
local copas = require("copas")
local crypto = require("nixio.crypto")
local ws_client = require("websocket.client.copas")
local ws_handshake = require("websocket.handshake.server")
local ws_sync = require("websocket.sync")

-- Utility to get system time
local function get_time() return os.time() end

-- Read configs
local cfg = "wol_ws"
local auth_key = uci:get(cfg, "config", "auth_key") or ""
local time_tolerance = tonumber(uci:get(cfg, "config", "time_tolerance") or "30") * 60
local rate_limit_time = tonumber(uci:get(cfg, "config", "rate_limit") or "0") * 60
local local_server = uci:get(cfg, "config", "local_server") == "1"
local local_port = tonumber(uci:get(cfg, "config", "local_port") or "8088")
local local_post = uci:get(cfg, "config", "local_post") == "1"
local ws_connect = uci:get(cfg, "config", "ws_connect") == "1"
local ws_servers = uci:get_list(cfg, "config", "ws_server") or {}

local last_wol_time = 0

-- HMAC SHA256 (nixio crypto HMAC wrapper)
local function calculate_sign(mac_addr, ts)
    local msg = mac_addr .. tostring(ts)
    if not auth_key or auth_key == "" then return "" end
    local hmac = crypto.hmac("sha256", auth_key)
    hmac:update(msg)
    return hmac:final("hex")
end

-- Validate the request payload
local function validate_req(payload)
    if not payload then return false, "No payload" end
    local req = json.parse(payload)
    if not req or req.action ~= "wol" or type(req.mac) ~= "string" or not req.mac:match("^%x%x:%x%x:%x%x:%x%x:%x%x:%x%x$") or not req.timestamp then
        return false, "Invalid payload format"
    end
    
    local now = get_time()
    if time_tolerance > 0 and math.abs(now - req.timestamp) > time_tolerance then
        return false, "Timestamp out of bounds"
    end

    if auth_key ~= "" then
        if req.sign ~= calculate_sign(req.mac, req.timestamp) then
            return false, "Invalid signature"
        end
    end

    if rate_limit_time > 0 then
        if (now - last_wol_time) < rate_limit_time then
            return false, "Rate limited"
        end
    end

    return true, req
end

-- Execute WOL
local function execute_wol(mac)
    last_wol_time = get_time()
    os.execute("etherwake " .. mac)
    print("WOL packet sent to " .. mac)
end

-- Handle incoming WS or HTTP payload
local function handle_payload(payload)
    local ok, req_or_err = validate_req(payload)
    if ok then
        execute_wol(req_or_err.mac)
        return json.stringify({status = "ok", message = "WOL broadcasted"})
    else
        return json.stringify({status = "error", message = req_or_err})
    end
end

-- Client connections
if ws_connect then
    for _, srv in ipairs(ws_servers) do
        copas.addthread(function()
            while true do
                local client = ws_client()
                local ok, err = client:connect(srv)
                if ok then
                    print("Connected to WS Remote: " .. srv)
                    while true do
                        local message, opcode = client:receive()
                        if not message or opcode == "close" then
                            break
                        end
                        if opcode == "text" then
                            local res = handle_payload(message)
                            client:send(res)
                        end
                    end
                    client:close()
                else
                    print("Failed to connect to " .. srv .. ": " .. tostring(err))
                end
                copas.sleep(5) -- 5 seconds backoff
            end
        end)
    end
end

-- Local Server
if local_server then
    local server_skt = socket.bind("*", local_port)
    if server_skt then
        print("Starting Local Server on port " .. local_port)
        copas.addserver(server_skt, function(skt)
            local client = copas.wrap(skt)
            local request_line = client:receive("*l")
            if not request_line then return end
            
            local method, path, http_ver = request_line:match("^([A-Z]+)%s+(%S+)%s+(%S+)$")
            
            local headers = {}
            while true do
                local line = client:receive("*l")
                if not line or line == "" then break end
                local k, v = line:match("^(.-):%s*(.*)$")
                if k then headers[k:lower()] = v end
            end
            
            if headers["upgrade"] and headers["upgrade"]:lower() == "websocket" then
                -- Perform WS Handshake
                local req = {
                    headers = headers,
                    url = path,
                    method = method
                }
                local response_headers = ""
                local protocols = {}
                local ws_response = function(res)
                    response_headers = "HTTP/1.1 " .. res.status .. "\r\n"
                    for k, v in pairs(res.headers) do
                        response_headers = response_headers .. k .. ": " .. v .. "\r\n"
                    end
                    response_headers = response_headers .. "\r\n"
                end
                
                local shake, err = ws_handshake.accept(req, ws_response, protocols)
                if shake then
                    client:send(response_headers)
                    local ws = ws_sync.extend(client)
                    while true do
                        local message, opcode = ws:receive()
                        if not message or opcode == "close" then break end
                        if opcode == "text" then
                            local res = handle_payload(message)
                            ws:send(res)
                        end
                    end
                else
                    client:send("HTTP/1.1 400 Bad Request\r\n\r\n")
                end
            elseif method == "POST" and local_post and path == "/wol" then
                local content_length = tonumber(headers["content-length"]) or 0
                local body = ""
                if content_length > 0 then
                    body = client:receive(content_length)
                end
                local res = handle_payload(body)
                local http_res = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: " .. string.len(res) .. "\r\n\r\n" .. res
                client:send(http_res)
            else
                local res = '{"status":"error","message":"Not Found or Method Not Allowed"}'
                client:send("HTTP/1.1 404 Not Found\r\nContent-Type: application/json\r\nContent-Length: " .. string.len(res) .. "\r\n\r\n" .. res)
            end
        end)
    else
        print("Failed to bind local server on port " .. local_port)
    end
end

print("WOL WS daemon loop running...")
copas.loop()


