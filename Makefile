TARGET=cdeps

CFLAGS += -Wall

CFLAGS += -Ibuild/include
LDFLAGS += -Lbuild/lib -llua
# FRAMEWORKS = -framework IOKit -framework Cocoa -framework OpenGL

.PHONY: all clean run

all: build/$(TARGET)

# Main target
build/$(TARGET): src/main.c src/config.c src/util.c
	$(CC) $(CFLAGS) $(LDFLAGS) $(FRAMEWORKS) $< -o $@

install: build/$(TARGET)
	cp build/$(TARGET) ~/bin/

clean:
	rm $(TARGET)

