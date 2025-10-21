# Use Node.js LTS Alpine image for smaller size
FROM node:18-alpine

# Create app directory
WORKDIR /usr/src/app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm install --production

# Copy app source
COPY app.js .

# Expose port
EXPOSE 3000

# Run the application
CMD [ "node", "app.js" ]

