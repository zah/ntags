SOURCE := $(wildcard *.nim)
TARGET = ntags

$(TARGET): $(SOURCE)
	nim cc -o:$(TARGET) $(SOURCE)

opt release:
	nim cc -o:$(TARGET) -d:release $(SOURCE)

clean:
	rm -f $(TARGET)

.PHONY: opt release clean
