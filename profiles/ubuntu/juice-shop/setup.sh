docker pull bkimminich/juice-shop

docker run -d \
  --name juice-shop \
  --restart unless-stopped \
  -p 3000:3000 \
  bkimminich/juice-shop
