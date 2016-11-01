----更新说明----
--2016-10-30:增加lcd1602的第二行,显示为日期和时间。其中日期和时间通过http.get()调用api得到。
--           更新的频率与dht更新频率一样,注册到tmr0,30秒更新一次
--      todo:固件中加入rtctime,从sntp中获取到时间,set到rtctime中
--create STATIONAP Mode--设置初始化station ap模式--
function staAp()
    cid = string.sub(node.chipid(),4,8)
    local YOUR_SSID = "Node_"..node.chipid()
    --local YOUR_PWD = "11111111"
    wifi.setmode(wifi.STATIONAP)
    wifi.ap.config({ssid=YOUR_SSID,auth=wifi.AUTH_OPEN})
    enduser_setup.manual(true)
    enduser_setup.start(
        function()
            print("Connected to wifi as:" .. wifi.sta.getip())
            gpio.write(led1, gpio.LOW)
        end,
        function(err, str)
            print("enduser_setup: Err #" .. err .. ": " .. str)
        end
    )
end;
--create sta server--创建sta服务器,响应网页--
function staServer()
    if srv then     --如果已经有一个服务器了，先停止
        srv:close()
    end
    srv=net.createServer(net.TCP)  
    srv:listen(80,function(conn)
        conn:on("receive", function(client,request)  
            local buf = "";  
            local _, _, method, path, vars = string.find(request, "([A-Z]+) (.+)?(.+) HTTP");  
            if(method == nil)then  
                _, _, method, path = string.find(request, "([A-Z]+) (.+) HTTP");  
            end  
            local _GET = {}  
            if (vars ~= nil)then  
                for k, v in string.gmatch(vars, "(%w+)=(%w+)&*") do  
                    _GET[k] = v  
                end  
            end 
            buf = buf.."<html><head><meta name='viewport' content='width=380'></head><style>.bt{width:100px;height:40px;}</style><body>"; 
            buf = buf.."<h1>".."Ivan_"..cid.." Web Server</h1>";  
            --DHT22
            --pin = 1
            status, temp, humi, temp_dec, humi_dec = dht.read(pin)
            if status == dht.OK then
                buf = buf.."<h2>Temp : "..temp.." ,  ".."Humi : "..humi.."</h2>";
            end
            buf = buf.."<h3>GPIO0 <a href=\"?pin=ON1\"><button class='bt'>ON</button></a> <a href=\"?pin=OFF1\"><button class='bt'>OFF</button></a></h3>"; 
            buf = buf.."</body></html>";
            local _on,_off = "",""  
            if(_GET.pin == "ON1")then  
                  gpio.write(led1, gpio.LOW);  
            elseif(_GET.pin == "OFF1")then  
                  gpio.write(led1, gpio.HIGH);  
            elseif(_GET.pin == "ON2")then  
                  gpio.write(led2, gpio.HIGH);  
            elseif(_GET.pin == "OFF2")then  
                  gpio.write(led2, gpio.LOW);  
            end
            client:send(buf);  
            client:close();  
            collectgarbage();  
        end)  
    end) 
end;     
--创建TCP客户端连接云服务器--
function tcpClient()
    if conn then
        conn:close()
    end
    conn=net.createConnection(net.TCP, false)
    conn:connect(1999,"cradle.jios.org")
    conn:on("receive", function(conn, data)
        print(data)
        local rs = cjson.decode(data)
        if rs['type'] == 'say' then
            local ct = rs['content']
            if ct then
                print(ct)
                if ct == "ledon" then
                    gpio.write(0, gpio.LOW)
                elseif ct == "ledoff" then
                    gpio.write(0, gpio.HIGH)
                end
            end
        end
    end)
    conn:on("connection", function(sck, c)
        print("TCP client connected!")
        login = '{"type":"login","client_name":"'..node.chipid()..'","room_id":"1"}'
        conn:send(login)
    end)
    conn:on("disconnection", function(sck, c)
        --print("tcp client close!")
        tmr.start(3) --delay 3 secends
    end)
end;

function printIp()      --打印ip到lcd--
    ipLen = string.len(wifi.sta.getip())
    if ipLen >13 then 
        dofile("lcd1602.lua").lcdprint("                ",2,0);
        dofile("lcd1602.lua").lcdprint(wifi.sta.getip(),2,0)
    else
        dofile("lcd1602.lua").lcdprint("IP:",2,0);
        dofile("lcd1602.lua").lcdprint(wifi.sta.getip(),2,3)
    end
end;

--get date time 取日期时间---
function getDate()
    http.get("http://cradle.jios.org:8899/api/time", nil, 
    function(code, data)
        if (code < 0) then
          print("HTTP request failed")
        else
          if data then
              if cjson.decode(data).status == '1' then
                  data1 = cjson.decode(data).time
                  data1 = string.sub(data1,1,16)
                  dofile("lcd1602.lua").lcdprint(data1,2,0)
              end
          end
        end
    end)
end;

-- functions end--
-- timer start -- 计时器代码 --
local n,m = 1,1
tmr.register(1, 3000, tmr.ALARM_AUTO, function()     
    if wifi.sta.getip() then        --如果取到IP则开始计时  
        if n == 1 then
            printIp()
            dofile("lcd1602.lua").lcdprint("^_^",1,13);
            gpio.write(led1, gpio.LOW);     --led灯亮
            wifi.setmode(wifi.STATION)      --改为station模式
            wifi.sta.connect()      --连接station到wifi上
            enduser_setup.stop()
            tcpClient()     --作为客户端连到云端
            staServer()     --发布一个局域网web页
        end
        if n == 10 then     --连接到路由超过10次循环
            enduser_setup.stop()    --关闭配置WIFI界面
        end
        n = n + 1
        m = 1   --有连接则重置m
    else
        if m == 1 then
            gpio.write(led1, gpio.HIGH)
            dofile("lcd1602.lua").lcdprint("0_0",1,13);
            dofile("lcd1602.lua").lcdprint("                ",2,0);
            dofile("lcd1602.lua").lcdprint("Disconnect!",2,0);
        elseif m ==10 then
            if srv then
                srv:close()
            end
            if conn then
                conn:close()
            end
            if wifi.getmode() ~= 3 then
                staAp()
            end
        end
        m = m + 1  
        n = 1   --无连接则重置n
    end
end);

tmr.register(3, 3000, tmr.ALARM_SINGLE, function()
    print("reconnecting...")
    tcpClient()
end);

tmr.register(4, 10000, tmr.ALARM_SINGLE, function()
    getDate()
end);
--timer end--

---------------------------这里开始是主代码---------------------------------
-------------------------------------------------------------------------
staAp() --开始初始化stationap模式
--LCD start-- 
dofile("lcd1602.lua").lcdprint("Hello Master!^_^",1,0)
dofile("lcd1602.lua").lcdprint("I am serving you",2,0)

tmr.register(2, 2000, tmr.ALARM_SINGLE, function()
    dofile("lcd1602.lua").lcdprint("             ",1,0);    
    dofile("lcd1602.lua").lcdprint("                ",2,0);
    dofile("lcd1602.lua").lcdprint("T:"..temp,1,0);
    dofile("lcd1602.lua").lcdprint("H:"..humi,1,7);
    dofile("lcd1602.lua").lcdprint("^_^",1,13);
    dofile("lcd1602.lua").lcdprint("IP:",2,0);
end)
tmr.start(2)

led1 = 0    --定义led针脚
pin = 1     --定义DHT读数针脚

gpio.mode(led1, gpio.OUTPUT)  
gpio.write(led1, gpio.HIGH)
status, temp, humi, temp_dec, humi_dec = dht.read(pin)

local t = 1
if status == dht.OK then    
    tmr.register(0, 30000, tmr.ALARM_AUTO, function() --注册tmr0 30秒一更新
        status, temp, humi, temp_dec, humi_dec = dht.read(pin)
        dofile("lcd1602.lua").lcdprint("  ",1,4)
        dofile("lcd1602.lua").lcdprint(temp,1,2)
        dofile("lcd1602.lua").lcdprint("  ",1,11)
        dofile("lcd1602.lua").lcdprint(humi,1,9)
        getDate() --取时间日期
--        if t%2 == 1 then
--            dofile("lcd1602.lua").lcdprint("0_0",1,13);
--        else
--            dofile("lcd1602.lua").lcdprint("^_^",1,13);
--        end
        t = t + 1
    end)
    tmr.start(0)
end
--调用计时器--
tmr.start(1) 
tmr.start(4)
----------------------------------------------------------------
