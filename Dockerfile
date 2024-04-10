FROM nginx:alpine
COPY default.conf /etc/nginx/conf.d/default.conf
RUN echo 'yo this is nginx' > /usr/share/nginx/html/index.html
EXPOSE 80
