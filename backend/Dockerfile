FROM node:20-slim

WORKDIR /app

# Install dependencies
COPY package*.json ./
RUN npm install

# Copy source code and pre-built public web/apk assets
COPY tsconfig.json ./
COPY src ./src
COPY public ./public

# Build TypeScript
RUN npm run build

EXPOSE 4000

ENV PORT=4000
ENV NODE_ENV=production

CMD ["npm", "start"]
