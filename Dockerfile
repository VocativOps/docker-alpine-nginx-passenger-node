FROM ruby:alpine

# node

ENV NODE_VERSION="6.7.0"
ENV NPM_VERSION="3.10.8"

RUN apk add --no-cache --virtual .node-builddeps curl make gcc g++ python linux-headers paxctl gnupg \
    && apk add --no-cache --virtual .node-rundeps libgcc libstdc++ \
    && gpg --keyserver ha.pool.sks-keyservers.net --recv-keys \
        9554F04D7259F04124DE6B476D5A82AC7E37093B \
        94AE36675C464D64BAFA68DD7434390BDBE9B9C5 \
        0034A06D9D9B0064CE8ADF6BF1747F4AD2306D93 \
        FD3A5288F042B6850C66B31F09FE44734EB7990E \
        71DCFD284A79C3B38668286BC97EC7A07EDE3FC1 \
        DD8F2338BAE7501E3DD5AC78C273792F7D83545D \
        C4F0DFFF4E8C1A8236409D08E73BC641CC11F4C8 \
        B9AE9905FFD7803F25714661B63B535A4C206CA9 \
    && curl -o node-v${NODE_VERSION}.tar.gz -sSL https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}.tar.gz \
    && curl -o SHASUMS256.txt.asc -sSL https://nodejs.org/dist/v${NODE_VERSION}/SHASUMS256.txt.asc \
    && gpg --verify SHASUMS256.txt.asc \
    && grep node-v${NODE_VERSION}.tar.gz SHASUMS256.txt.asc | sha256sum -c - \
    && tar -zxf node-v${NODE_VERSION}.tar.gz \
    && cd node-v${NODE_VERSION} \
    && export GYP_DEFINES="linux_use_gold_flags=0" \
    && ./configure \
        --prefix=/usr \
    && make -j$(getconf _NPROCESSORS_ONLN) -C out mksnapshot BUILDTYPE=Release \
    && paxctl -cm out/Release/mksnapshot \
    && make -j$(getconf _NPROCESSORS_ONLN) \
    && make install \
    && paxctl -cm /usr/bin/node \
    && cd / \
    && if [ -x /usr/bin/npm ]; then \
        npm install -g npm@${NPM_VERSION} \
        && find /usr/lib/node_modules/npm -name test -o -name .bin -type d | xargs rm -rf; \
    fi \
    && apk del .node-builddeps \
    && rm -rf \
        /node-v${NODE_VERSION}.tar.gz \
        /SHASUMS256.txt.asc \
        /node-v${NODE_VERSION} \
        /root/.npm \
        /root/.node-gyp \
        /usr/lib/node_modules/npm/man \
        /usr/lib/node_modules/npm/doc \
        /usr/lib/node_modules/npm/html

WORKDIR /usr/src/app

ONBUILD COPY package.json /usr/src/app
ONBUILD RUN npm install
ONBUILD COPY . /usr/src/app

# passenger

ENV PASSENGER_VERSION 5.0.30

ENV PATH "/opt/passenger/bin:$PATH"

RUN echo "http://alpine.gliderlabs.com/alpine/edge/main" > /etc/apk/repositories \
    \
    && apk add --no-cache --virtual .passenger-rundeps ca-certificates ruby procps curl pcre libstdc++ libexecinfo \
    && update-ca-certificates \
    && apk add --no-cache --virtual .passenger-builddeps build-base ruby-dev linux-headers curl-dev pcre-dev libexecinfo-dev \
    \
    && mkdir -p /opt \
    && curl -sSL https://github.com/phusion/passenger/archive/release-${PASSENGER_VERSION}.tar.gz | tar -zx -C /opt \
    && mv /opt/passenger-release-${PASSENGER_VERSION} /opt/passenger \
    \
    && export EXTRA_PRE_CFLAGS="-O" \
    && export EXTRA_PRE_CXXFLAGS="-O" \
    && export EXTRA_LDFLAGS="-lexecinfo" \
    \
    && passenger-config compile-agent --auto --optimize \
    && passenger-config install-standalone-runtime --auto --url-root=fake --connect-timeout=1 \
    && passenger-config build-native-support \
    \
    && mkdir -p /usr/src/app \
    \
    && rm -rf /tmp/* \
    \
    && mv /opt/passenger/src/ruby_supportlib /tmp \
    && mv /opt/passenger/src/nodejs_supportlib /tmp \
    && mv /opt/passenger/src/ruby_native_extension /tmp \
    && mv /opt/passenger/src/helper-scripts /tmp \
    && rm -rf /opt/passenger/src/* \
    \
    && mv /tmp/* /opt/passenger/src/ \
    \
    && passenger-config validate-install --auto \
    && apk del .passenger-builddeps \
    && rm -rf /usr/include/execinfo.h \
        /opt/passenger/doc

RUN rm -rf \
    /var/cache/apk/* \
    /tmp/* \
    /etc/ssl \
    /root/.gnupg \
    /usr/share/man

# nginx

ENV NGINX_VERSION 1.11.4

RUN GPG_KEYS=B0F4253373F8F6F510D42178520A9993A1C052F8 \
    && CONFIG="\
        --prefix=/etc/nginx \
        --sbin-path=/usr/sbin/nginx \
        --modules-path=/usr/lib/nginx/modules \
        --conf-path=/etc/nginx/nginx.conf \
        --error-log-path=/var/log/nginx/error.log \
        --http-log-path=/var/log/nginx/access.log \
        --pid-path=/var/run/nginx.pid \
        --lock-path=/var/run/nginx.lock \
        --http-client-body-temp-path=/var/cache/nginx/client_temp \
        --http-proxy-temp-path=/var/cache/nginx/proxy_temp \
        --http-fastcgi-temp-path=/var/cache/nginx/fastcgi_temp \
        --http-uwsgi-temp-path=/var/cache/nginx/uwsgi_temp \
        --http-scgi-temp-path=/var/cache/nginx/scgi_temp \
        --user=nginx \
        --group=nginx \
        --with-http_ssl_module \
        --with-http_realip_module \
        --with-http_addition_module \
        --with-http_sub_module \
        --with-http_dav_module \
        --with-http_flv_module \
        --with-http_mp4_module \
        --with-http_gunzip_module \
        --with-http_gzip_static_module \
        --with-http_random_index_module \
        --with-http_secure_link_module \
        --with-http_stub_status_module \
        --with-http_auth_request_module \
        --with-http_xslt_module=dynamic \
        --with-http_image_filter_module=dynamic \
        --with-http_geoip_module=dynamic \
        --with-http_perl_module=dynamic \
        --with-threads \
        --with-stream \
        --with-stream_ssl_module \
        --with-stream_realip_module \
        --with-stream_geoip_module=dynamic \
        --with-http_slice_module \
        --with-mail \
        --with-mail_ssl_module \
        --with-file-aio \
        --with-http_v2_module \
        --with-ipv6 \
        --add-module=$(passenger-config --nginx-addon-dir) \
    " \
    && addgroup -S nginx \
    && adduser -D -S -h /var/cache/nginx -s /sbin/nologin -G nginx nginx \
    && apk add --no-cache --virtual .nginx-builddeps \
        gcc \
        libc-dev \
        make \
        openssl-dev \
        pcre-dev \
        zlib-dev \
        linux-headers \
        curl \
        gnupg \
        libxslt-dev \
        gd-dev \
        geoip-dev \
        perl-dev \
    && curl -fSL http://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz -o nginx.tar.gz \
    && curl -fSL http://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz.asc  -o nginx.tar.gz.asc \
    && export GNUPGHOME="$(mktemp -d)" \
    && gpg --keyserver ha.pool.sks-keyservers.net --recv-keys "${GPG_KEYS}" \
    && gpg --batch --verify nginx.tar.gz.asc nginx.tar.gz \
    && rm -r "${GNUPGHOME}" nginx.tar.gz.asc \
    && mkdir -p /usr/src \
    && tar -zxC /usr/src -f nginx.tar.gz \
    && rm nginx.tar.gz \
    && cd /usr/src/nginx-${NGINX_VERSION} \
    && ./configure ${CONFIG} --with-debug \
    && make -j$(getconf _NPROCESSORS_ONLN) \
    && mv objs/nginx objs/nginx-debug \
    && mv objs/ngx_http_xslt_filter_module.so objs/ngx_http_xslt_filter_module-debug.so \
    && mv objs/ngx_http_image_filter_module.so objs/ngx_http_image_filter_module-debug.so \
    && mv objs/ngx_http_geoip_module.so objs/ngx_http_geoip_module-debug.so \
    && mv objs/ngx_http_perl_module.so objs/ngx_http_perl_module-debug.so \
    && mv objs/ngx_stream_geoip_module.so objs/ngx_stream_geoip_module-debug.so \
    && ./configure ${CONFIG} \
    && make -j$(getconf _NPROCESSORS_ONLN) \
    && make install \
    && rm -rf /etc/nginx/html/ \
    && mkdir /etc/nginx/conf.d/ \
    && mkdir -p /usr/share/nginx/html/ \
    && install -m644 html/index.html /usr/share/nginx/html/ \
    && install -m644 html/50x.html /usr/share/nginx/html/ \
    && install -m755 objs/nginx-debug /usr/sbin/nginx-debug \
    && install -m755 objs/ngx_http_xslt_filter_module-debug.so /usr/lib/nginx/modules/ngx_http_xslt_filter_module-debug.so \
    && install -m755 objs/ngx_http_image_filter_module-debug.so /usr/lib/nginx/modules/ngx_http_image_filter_module-debug.so \
    && install -m755 objs/ngx_http_geoip_module-debug.so /usr/lib/nginx/modules/ngx_http_geoip_module-debug.so \
    && install -m755 objs/ngx_http_perl_module-debug.so /usr/lib/nginx/modules/ngx_http_perl_module-debug.so \
    && install -m755 objs/ngx_stream_geoip_module-debug.so /usr/lib/nginx/modules/ngx_stream_geoip_module-debug.so \
    && ln -s ../../usr/lib/nginx/modules /etc/nginx/modules \
    && strip /usr/sbin/nginx* \
    && strip /usr/lib/nginx/modules/*.so \
    && rm -rf /usr/src/nginx-${NGINX_VERSION} \
    \
    # Bring in gettext so we can get `envsubst`, then throw
    # the rest away. To do this, we need to install `gettext`
    # then move `envsubst` out of the way so `gettext` can
    # be deleted completely, then move `envsubst` back.
    && apk add --no-cache --virtual .gettext gettext \
    && mv /usr/bin/envsubst /tmp/ \
    \
    && rundeps="$( \
        scanelf --needed --nobanner /usr/sbin/nginx /usr/lib/nginx/modules/*.so /tmp/envsubst \
            | awk '{ gsub(/,/, "\nso:", $2); print "so:" $2 }' \
            | sort -u \
            | xargs -r apk info --installed \
            | sort -u \
    )" \
    && apk add --no-cache --virtual .nginx-rundeps ${rundeps} \
    && apk del .nginx-builddeps \
    && apk del .gettext \
    && mv /tmp/envsubst /usr/local/bin/ \
    \
    # forward request and error logs to docker log collector
    && ln -sf /dev/stdout /var/log/nginx/access.log \
    && ln -sf /dev/stderr /var/log/nginx/error.log

ONBUILD COPY nginx.conf /etc/nginx/nginx.conf
ONBUILD COPY nginx.vh.*.conf /etc/nginx/conf.d/

# app

EXPOSE 80 443

ENTRYPOINT ["nginx", "-g", "daemon off;"]
