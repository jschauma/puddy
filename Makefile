NAME=puddy
PREFIX?=/usr/local
PERL!=which perl

help:
	@echo "The following targets are available:"
	@echo "clean    remove temporary files"
	@echo "prep     update the perl path in the source script"
	@echo "install  install all files under ${PREFIX}"

prep: src/${NAME}

src/${NAME}: src/${NAME}.pl
	sed -e "s|/usr/local/bin/perl|${PERL}|" $? >$@

install: prep
	mkdir -p ${PREFIX}/bin ${PREFIX}/share/man/man1
	install -m 755 src/${NAME} ${PREFIX}/bin/${NAME}
	install -m 444 doc/${NAME}.1 ${PREFIX}/share/man/man1
	install -m 444 conf/${NAME}.resolvers ${PREFIX}/share/${NAME}.resolvers

clean:
	rm -f src/${NAME}
