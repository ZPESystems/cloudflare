FROM alpine:latest
RUN mkdir -p /var/log 
RUN echo "" > /var/log/dnsmasq.log
RUN apk --no-cache add dnsmasq iptables \
    && echo "conf-dir=/etc/dnsmasq,*.conf" > /etc/dnsmasq.conf
ENTRYPOINT ["/usr/bin/tail", "-f", "/var/log/dnsmasq.log"]
