# Use the official Nginx image based on Alpine for smaller image size
FROM nginx:alpine

# Remove the default server definition which is intended to show the 'Welcome to nginx' page
RUN rm /etc/nginx/conf.d/default.conf

# Create a new default.conf file
RUN echo $'server {\n\
    listen 80;\n\
    location / {\n\
        add_header Content-Type text/plain;\n\
        return 200 "yo this is nginx";\n\
    }\n\
}' > /etc/nginx/conf.d/default.conf

# Expose port 80 on the container
EXPOSE 80

# Start Nginx in the foreground to keep the container running.
CMD ["nginx", "-g", "daemon off;"]
