FROM node:20-slim

WORKDIR /app

COPY package.json package-lock.json* ./
RUN npm install --omit=dev

COPY signaling.js .

EXPOSE 7860

ENV PORT=7860

CMD ["node", "signaling.js"]
