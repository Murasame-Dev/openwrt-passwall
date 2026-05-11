local m, s, o

m = Map("wol_ws", translate("WOL WebSocket and HTTP Server"),
	translate("This plugin acts as a client or server to receive WOL requests via WebSocket or HTTP POST, with HMAC-SHA256 authentication and timestamp verification."))

s = m:section(TypedSection, "config", translate("Global Settings"))
s.anonymous = true

o = s:option(Flag, "enabled", translate("Enable"))
o.default = 0
o.rmempty = false

o = s:option(Value, "auth_key", translate("Authentication Key (Secret)"))
o.password = true
o.rmempty = true

o = s:option(Value, "time_tolerance", translate("Timestamp Tolerance (Minutes)"),
	translate("Max allowed difference between request timestamp and system time. 0 means unlimited."))
o.datatype = "uinteger"
o.default = "30"
o.rmempty = false

o = s:option(Value, "rate_limit", translate("Global Call Limit (Minutes)"),
	translate("Limit valid WOL requests over this timeframe. Setting 0 disables the limit."))
o.datatype = "uinteger"
o.default = "0"
o.rmempty = false

o = s:option(Flag, "local_server", translate("Enable Local WebSocket/HTTP Server"))
o.default = 0
o.rmempty = false

o = s:option(Value, "local_port", translate("Local Server Port"))
o.datatype = "port"
o.default = "8088"
o:depends("local_server", "1")

o = s:option(Flag, "local_post", translate("Enable HTTP POST Support"),
	translate("If enabled, allows HTTP POST to /wol on the local server port."))
o.default = 0
o:depends("local_server", "1")

o = s:option(Flag, "ws_connect", translate("Active WebSocket Connect"))
o.default = 0
o.rmempty = false

o = s:option(DynamicList, "ws_server", translate("WebSocket Server Addresses"),
	translate("e.g., ws://your-server.com:8080/ws"))
o:depends("ws_connect", "1")

m.append = Template("wol_ws/js_enhancement")

return m