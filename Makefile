SOURCE := $(wildcard *.nim)
TARGET = ntags

$(TARGET): $(SOURCE)
	nim cc $(SOURCE)

opt release:
	nim cc -d:release $(SOURCE)

clean:
	rm -f $(TARGET)

.PHONY: opt release clean
