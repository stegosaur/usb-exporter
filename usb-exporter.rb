#!/usr/bin/env ruby
require 'sinatra'
require 'timeout'

set :bind, '0.0.0.0'
set :port, ENV['METRICS_PORT'] unless ENV['METRICS_PORT'].nil? 

enable :logging, :dump_errors, :raise_errors

def lsusb_buses()
  buses=IO.popen(%W[lsusb])
  b=buses.read.split("\n").map{|line| line.split(' ')[1].to_i }.uniq
  buses.close
  return b
end

def lsusb(device,bus)
  lsusb=IO.popen(%W[lsusb -vs #{bus}:#{device}])
  l=lsusb.read.scan(/bcdUSB.*|iManufact.*?\n|iProduct.*|iSerial.*/)
  l=l.map{|x| x=x.strip.gsub(/ \d /,'').split(/\s{2,}/) }.to_h
  lsusb.close
  return l
end

def usb_debug(time=5)
  t0=Time.now
  debug={}
  sample=[]
  begin
    Timeout::timeout(time) {
      File.foreach("/sys/kernel/debug/usb/usbmon/0u") {|line| 
        sample << line 
        break if Time.now-t0>time 
      }
    }
  rescue
  end
  usbinfo=get_usb_info() 
  usbinfo.keys.each{|bus| _bus=bus.to_s.rjust(1,"0")
    usbinfo[bus].keys.each{|port| _port=port.to_s.rjust(3,"0")
      debug["#{_bus}:#{_port}"] = {}
      current_sample=sample.grep(/#{_bus}:#{_port}/)
      success=current_sample.select{|line| line.split(" ")[4] == "0"}
      bits=success.map{|row| row.split(" ")[5].to_i }.sum
      debug["#{_bus}:#{_port}"]["rate"] = bits.to_f / time
      debug["#{_bus}:#{_port}"]["count"] = success.size.to_f / time
      debug["#{_bus}:#{_port}"]["driver"] = usbinfo[bus][port]['driver']
      debug["#{_bus}:#{_port}"]["tags"]="port=\"#{usbinfo[bus][port]['port']}\","
      debug["#{_bus}:#{_port}"]["tags"]+="bus_id=\"#{bus}\","
      debug["#{_bus}:#{_port}"]["tags"]+="usbstd=\"#{usbinfo[bus][port]['usbstd']}\","
      debug["#{_bus}:#{_port}"]["tags"]+="speed=\"#{usbinfo[bus][port]['speed']}\","
      debug["#{_bus}:#{_port}"]["tags"]+="manufacturer=\"#{usbinfo[bus][port]['manufacturer']}\","
      debug["#{_bus}:#{_port}"]["tags"]+="product=\"#{usbinfo[bus][port]['product']}\","
      debug["#{_bus}:#{_port}"]["tags"]+="serial=\"#{usbinfo[bus][port]['serial']}\","
      debug["#{_bus}:#{_port}"]["tags"]+="driver=\"#{usbinfo[bus][port]['driver']}\""
    }
  }
  return debug
end

def monitor_from_debug(time=5)
  results=usb_debug(time)
  output=[]
  results.each{|device,data|
    bus=device.split(":")[0].to_i.to_s
    port=device.split(":")[1].to_i.to_s
    output << "usb_bits_per_sec{#{data["tags"]}} #{data["rate"]}"
    output << "usb_packets_successful_per_sec{#{data["tags"]}} #{data["count"]}"
    if data['driver'] == "uvcvideo"
      frames=get_uvcvideo_frames(bus,port)
      output << "uvcvideo_frames_reported{#{data["tags"]}} #{frames}"
    end
  }
  return output.join("\n")
end
  
def get_uvcvideo_frames(bus,port)
    uvcvideo=File.open("/sys/kernel/debug/usb/uvcvideo/#{bus}-#{port}/stats").read rescue uvcvideo=File.open("/sys/kernel/debug/usb/uvcvideo/#{bus}-#{port}-1/stats").read
    frames=uvcvideo.match(/frames:.*/).to_s.match(/\d+/)[0]
    return frames
end

def get_usb_info()
  begin
    usbraw=File.open("/sys/kernel/debug/usb/devices").read
  rescue
    return nil
  end
  usbinfo={}
  scanregex=/Bus=\d+|Manufacturer=.*|Product=.*|SerialNumber=.*|Dev#=.*?\d+|Spd=\d+|Ver= .*? |Driver=.*/
  usbraw.scan(scanregex).each{ |line|
    if line.match("Bus=")
      @bus=line.match(/\d+/).to_s.to_i.to_s
      usbinfo["#{@bus}"]={} if usbinfo["#{@bus}"].nil?
    elsif line.match("Dev#=")
      @port=line.match(/\d+/).to_s.to_i
      @port=@port.to_s
      usbinfo["#{@bus}"]["#{@port}"]={} if usbinfo["#{@bus}"]["#{@port}"].nil?
      usbinfo["#{@bus}"]["#{@port}"]["port"]=@port
    elsif line.match("Spd=")
      speed=line.match(/\d+/).to_s
      usbinfo["#{@bus}"]["#{@port}"]["speed"]=speed
    elsif line.match("Ver=")
      ver=line.match(/\d+.*\d+/).to_s
      usbinfo["#{@bus}"]["#{@port}"]["usbstd"]=ver
    elsif line.match("Manufacturer=")
      manu=line.split("=")[-1].strip
      usbinfo["#{@bus}"]["#{@port}"]["manufacturer"]=manu
    elsif line.match("Product=")
      product=line.split("=")[-1].strip
      usbinfo["#{@bus}"]["#{@port}"]["product"]=product
    elsif line.match("SerialNumber=")
      serial=line.split("=")[-1].strip
      usbinfo["#{@bus}"]["#{@port}"]["serial"]=serial
    elsif line.match("Driver=")
      driver=line.split("=")[-1].strip
      usbinfo["#{@bus}"]["#{@port}"]["driver"]=driver
    end
  }
  return usbinfo
end

get '/metrics' do
  output=[]
  usbinfo=get_usb_info()
  buses=usbinfo.keys unless buses.nil?
  buses=lsusb_buses() if buses.nil?
  time=(7/buses.size + 1) if params['time'].nil?
  time=params['time'] unless params['time'].nil?
  if usbinfo.nil?
    buses.each{|b| output << monitor_usb_via_usbtop(b, time) } if params['bus'].nil?
    output << monitor_usb_via_usbtop(params['bus']) unless params['bus'].nil?
  else
    output << monitor_from_debug(time)
  end
  body output.join("\n")
end
