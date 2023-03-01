# usb-exporter
usb bandwidth monitoring exporter for prometheus (linux only)

the linux usbmon kernel module needs to be activated for this tool to operate. it may be activated with `modprobe usbmon`. more information about this module may be found here https://www.kernel.org/doc/html/latest/usb/usbmon.html

default port is 4567, change it using an env var for METRICS_PORT.

within docker, you need to give the container access to /sys/kernel/debug

example docker run cmd:
`docker run --entrypoint /bin/usb_exporter.rb --privileged -d -p 4567:4567 -v /sys/kernel/debug/:/sys/kernel/debug usb-exporter:x86`
