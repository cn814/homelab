#!/bin/bash
# usgovernment archiver - limited mode (6am-midnight)
docker stop usgovernment && docker rm usgovernment
docker run -d \
  --name usgovernment \
  --restart unless-stopped \
  atdr.meo.ws/archiveteam/usgovernment-grab \
  --concurrent 20 cneal
