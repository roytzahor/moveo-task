FROM amazonlinux:2  # Amazon Linux as the base image
RUN yum install -y nginx  # Install Nginx using yum
RUN echo 'yo this is nginx' > /usr/share/nginx/html/index.html
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
