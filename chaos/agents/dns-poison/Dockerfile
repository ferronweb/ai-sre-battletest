FROM alpine:latest
RUN apk --no-cache add dnsmasq
COPY dnsmasq.conf /etc/dnsmasq.conf
EXPOSE 53/udp 53/tcp
ENTRYPOINT ["dnsmasq", "-k", "-C", "/etc/dnsmasq.conf"]
