SHELL := /bin/bash

URL ?= http://paffenroth-23.dyn.wpi.edu:8010/
RECOVER := /home/ujjwal/mlops_assignment2/scripts/recover.sh
SMOKE := /home/ujjwal/mlops_assignment2/scripts/smoke_test.sh
DEPLOY := /home/ujjwal/mlops_assignment2/deploy.sh

.PHONY: deploy smoke recover status logs restart

deploy:
	@if [ -z "$$HUGGING_FACE_TOKEN" ]; then echo "ERROR: HUGGING_FACE_TOKEN not set"; exit 1; fi
	$(DEPLOY)

smoke:
	bash $(SMOKE) $(URL)

recover:
	bash $(RECOVER)

status:
	ssh -i ~/.ssh/my_key -p 22010 student-admin@paffenroth-23.dyn.wpi.edu \
	  'systemctl --user status --no-pager hugging_face_mood_app.service'

logs:
	ssh -i ~/.ssh/my_key -p 22010 student-admin@paffenroth-23.dyn.wpi.edu \
	  'tail -n 200 ~/hugging_face_mood_app/app.log'

restart:
	ssh -i ~/.ssh/my_key -p 22010 student-admin@paffenroth-23.dyn.wpi.edu \
	  'systemctl --user restart hugging_face_mood_app.service'


