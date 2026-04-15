#--------------------------------------------
# Dev Stage - Assembles and Builds Frontend
#--------------------------------------------
FROM --platform=$BUILDPLATFORM node:22-alpine as dev

ARG APP_SHELL_VERSION=9.0.2

RUN mkdir -p /app
WORKDIR /app

COPY spa-assemble-config.json .
COPY spa-build-config.json .

ARG CACHE_BUST
RUN npm config set fetch-timeout 300000 && \
    npm config set fetch-retry-mintimeout 20000 && \
    npm config set fetch-retry-maxtimeout 120000 && \
    npm config set fetch-retries 5
RUN mkdir -p configuration
COPY ./configuration/*.json configuration
RUN npx --legacy-peer-deps openmrs@${APP_SHELL_VERSION:-9.0.2} assemble --manifest --mode config --config spa-assemble-config.json --config-file configuration/*.json --target ./spa
# Install @react-aria/utils peer dependency required by @openmrs/esm-styleguide datepicker
RUN NPX_CACHE=$(find /root/.npm/_npx -maxdepth 1 -type d | tail -1) && \
    cd "$NPX_CACHE/node_modules/@openmrs/esm-styleguide" && \
    npm install --legacy-peer-deps @react-aria/utils
RUN npx --legacy-peer-deps openmrs@${APP_SHELL_VERSION:-9.0.2} build --build-config spa-build-config.json --target ./spa
RUN if [ ! -f ./spa/index.html ]; then echo 'Build failed. Please check the logs above for details. This may have happened because of an update to a library that OpenMRS depends on.'; exit 1; fi

#--------------------------------------------
# Runtime Stage - Published Image
#--------------------------------------------
FROM nginx:1.25-alpine

RUN apk update && \
    apk upgrade && \
    # add more utils for sponge and envsubst
    apk add --no-cache moreutils

# clear any default files installed by nginx
RUN rm -rf /usr/share/nginx/html/*

COPY startup.sh /usr/local/bin/startup.sh
RUN chmod +x /usr/local/bin/startup.sh

COPY nginx.conf /etc/nginx/nginx.conf

COPY --from=dev /app/spa /usr/share/nginx/html
# COPY config-core_demo.json /usr/share/nginx/html
COPY *.json /usr/share/nginx/html
COPY ./configuration/*.json /usr/share/nginx/html
# COPY ./assets /usr/share/nginx/html

CMD ["/usr/local/bin/startup.sh"]
