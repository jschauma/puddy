NAME=puddy
PREFIX?=/usr/local

help:
	@echo "The following targets are available:"
	@echo "install  install all files under ${PREFIX}"

install:
	mkdir -p ${PREFIX}/bin ${PREFIX}/share/man/man1
	install -m 755 src/${NAME}.pl ${PREFIX}/bin/${NAME}
	install -m 444 doc/${NAME}.1 ${PREFIX}/share/man/man1
	install -m 444 conf/${NAME}.resolvers ${PREFIX}/share/${NAME}.resolvers
