FROM ruby:2.6.10

RUN gem install sinatra --no-document && \
    apt update && \
    apt install -y usbutils

COPY ./usb_exporter.rb /bin/usb_exporter.rb

RUN chmod 755 /bin/usb_exporter.rb
