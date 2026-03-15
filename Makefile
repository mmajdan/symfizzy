.PHONY: deploy-all deploy-web deploy-symphony deploy-sym workflows

deploy-all:
	bin/kamal deploy

deploy-web:
	bin/kamal deploy -r web

deploy-symphony:
	bin/kamal deploy -r symphony

deploy-sym: deploy-symphony

restart-sym:
	bin/kamal app boot -r symphony

workflows:
	ssh nexus 'mkdir -p ~/backup && TIMESTAMP=$$(date +%Y%m%d_%H%M%S) && rsync -av ~/workflows/ ~/backup/workflows.$$TIMESTAMP/'
	rsync -av --delete ./workflows/ nexus:~/workflows/
