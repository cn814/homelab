#!/bin/bash
# usgovernment archiver - unlimited mode (midnight-6am)
docker stop usgovernment && docker rm usgovernment
docker run -d \
  --name usgovernment \
  --restart unless-stopped \
  atdr.meo.ws/archiveteam/usgovernment-grab \
  --concurrent 20 cneal
