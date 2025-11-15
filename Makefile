.PHONY: up halt destroy ssh reload

up:
	vagrant up

halt:
	vagrant halt

destroy:
	vagrant destroy

ssh:
	vagrant ssh

reload:
	vagrant reload
