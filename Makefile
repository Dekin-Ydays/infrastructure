start:
	ansible-playbook playbooks/site.yml --ask-vault-pass

healthcheck:
	ansible-playbook playbooks/healthcheck.yml
