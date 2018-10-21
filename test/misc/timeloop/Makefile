CC=gcc

default: build

build: clean_timeloop
	$(CC) -o timeloop timeloop.c
	chmod +x timeloop
	sudo docker build --file Dockerfile-timeloop.test -t test_timeloop .

clean: clean_timeloop
	sudo docker image rm test_timeloop

clean_timeloop:
	rm -f timeloop
