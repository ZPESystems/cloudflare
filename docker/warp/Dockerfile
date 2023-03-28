FROM debian:stable-slim
RUN apt update && apt install -y \
   wget \
   curl \
   gpg \
   iptables \
   gnupg2 \
   dnsmasq \
   lsb-release \
   iproute2 \
   iputils-ping \
   links 
#   net-tools \
#   wireguard-tools \
#   openresolv  \
#   dnsutils \

RUN wget https://developers.cloudflare.com/cloudflare-one/static/documentation/connections/Cloudflare_CA.pem -O /usr/local/share/ca-certificates/Cloudflare_CA.crt

RUN DEBIAN_FRONTEND='noninteractive' DEBCONF_NONINTERACTIVE_SEEN='true' dpkg-reconfigure --frontend=noninteractive ca-certificates

RUN curl https://pkg.cloudflareclient.com/pubkey.gpg | gpg --yes --dearmor --output /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg

RUN echo "deb [arch=amd64 signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/cloudflare-client.list

RUN apt update && apt install -y cloudflare-warp

#COPY mdm.xml /var/lib/cloudflare-warp/mdm.xml

CMD ["/bin/warp-svc"]
