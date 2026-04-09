.PHONY: deploy-all deploy-web deploy-symphony deploy-sym deploy-symfizzy restart-sym restart-symfizzy restart-all clean-symphony-workspaces workflows

DEPLOY_HOST ?= nexus.majdan.online
APP_CONTAINERS_CMD = docker ps -aq --filter label=service=fizzy --filter label=destination=

deploy-all:
	ssh $(DEPLOY_HOST) 'containers=$$($(APP_CONTAINERS_CMD)); if [ -n "$$containers" ]; then docker rm -f $$containers; fi'
	$(MAKE) clean-symphony-workspaces
	bin/kamal deploy

deploy-web:
	bin/kamal deploy -r web

deploy-symphony:
	bin/kamal deploy -r symphony

deploy-sym: deploy-symphony

deploy-symfizzy:
	bin/kamal deploy -r symfizzy

restart-sym:
	bin/kamal app boot -r symphony

restart-symfizzy:
	bin/kamal app boot -r symfizzy

restart-all:
	ssh $(DEPLOY_HOST) 'containers=$$($(APP_CONTAINERS_CMD)); if [ -n "$$containers" ]; then docker rm -f $$containers; fi'

clean-symphony-workspaces:
	ssh $(DEPLOY_HOST) 'docker rm -f $$(docker ps -aq --filter volume=fizzy_symphony_workspaces) 2>/dev/null || true'
	ssh $(DEPLOY_HOST) 'docker volume rm -f fizzy_symphony_workspaces >/dev/null 2>&1 || true'
	ssh $(DEPLOY_HOST) 'docker volume create fizzy_symphony_workspaces >/dev/null'

workflows:
	ssh nexus 'mkdir -p ~/backup && TIMESTAMP=$$(date +%Y%m%d_%H%M%S) && rsync -av ~/workflows/ ~/backup/workflows.$$TIMESTAMP/'
	rsync -av --delete ./workflows/ nexus:~/workflows/
