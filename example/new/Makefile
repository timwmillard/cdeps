TARGET=hello

CFLAGS += -Wall

CFLAGS += -Ibuild/include
LDFLAGS += -Lbuild/lib
# FRAMEWORKS = -framework IOKit -framework Cocoa -framework OpenGL

.PHONY: all clean run

all: build/$(TARGET)

# Main target
build/$(TARGET): src/main.c
	$(CC) $(CFLAGS) $(LDFLAGS) $(FRAMEWORKS) $< -o $@

install:
	cp build/$(TARGET) ~/bin

clean:
	rm $(TARGET)

