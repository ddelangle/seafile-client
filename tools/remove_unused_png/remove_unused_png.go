package main

import (
	"encoding/xml"
	"flag"
	"io/ioutil"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"errors"
)

var verbose_mode bool = false
var dry_run_mode bool = false
var force_mode bool = false

func which(program string) (string, error) {
    Paths := strings.Split(os.Getenv("PATH"), string(os.PathListSeparator))
    for _, Path := range Paths {
      ProgPath := Path + string(os.PathSeparator) + program
      stat, err := os.Stat(ProgPath)
      if err != nil {
        continue
      }
      if stat.Mode().Perm() | 0x0111 != 0 {
        return ProgPath, nil
      }

    }
	return os.DevNull, errors.New("not found")
}

type qresource struct {
	XMLName xml.Name `xml:"qresource"`
	Files   []string `xml:"file"`
}

type qrc struct {
	XMLName  xml.Name  `xml:"RCC"`
	Resource qresource `xml:"qresource"`
}

func get_images_from_qrc(name string) ([]string, error) {

	qrcFile, err := os.Open("seafile-client.qrc")
	if err != nil {
		log.Printf("Error opening file: \n", err)
		return nil, err
	}
	defer qrcFile.Close()

	qrcRawData, _ := ioutil.ReadAll(qrcFile)

	images := make([]string, 0, 100)

	var qrcData qrc
	xml.Unmarshal(qrcRawData, &qrcData)
	for _, File := range qrcData.Resource.Files {
		if strings.HasPrefix(File, "images/") {
			images = append(images, File)
			if verbose_mode {
				log.Printf("appending mode: %s \n", File)
			}
		}
	}
	return images, nil
}

func check_image_from_src(name string, force bool) bool {
	if strings.HasPrefix(name, "images/win/") ||
		strings.HasPrefix(name, "images/files/") ||
		strings.HasPrefix(name, "images/files_v2/") ||
		strings.HasPrefix(name, "images/sync/") {
		return true
	}
	if strings.Contains(name, "caret-") {
		return true
	}
	result := true
	search_command := exec.Command("ag", "\":/"+name+"\"", "src")
	err := search_command.Run()
	if err != nil {
		if verbose_mode {
			log.Printf("not found %s in src \n", name)
		}
		result = false
	}
	if strings.HasSuffix(name, "@2x.png") {
		return true
	}
	if !result {
		basename := filepath.Base(name)
		if verbose_mode {
			log.Printf("trying to search its basename %s for fallback\n", basename)
		}
		search_command := exec.Command("ag", basename, "src")
		err := search_command.Run()
		if err != nil {
			if verbose_mode {
				log.Printf("still not found %s in src \n", basename)
			}
		} else {
			if verbose_mode {
				log.Printf("ambiguous case found: %s", basename)
			}
			if !force_mode {
				result = true
			}
		}
	}
	return result
}

func change_dir_for_file(name string) error {
	_, err := os.Stat("seafile-client.qrc")
	if err != nil {
		// try to find the top dir of the project
		dir, err := filepath.Abs(filepath.Dir(os.Args[0]) + "/../..")
		if err != nil {
			return err
		}
		// check the file
		_, err = os.Stat(dir + string(os.PathSeparator) + name)
		if err != nil {
			return err
		}

		// chdir to it
		err = os.Chdir(dir)
		if err != nil {
			return err
		}
	}
	return nil
}

func main() {
	err := change_dir_for_file("seafile-client.qrc")
	if err != nil {
		log.Println("print run this tool under the root the project")
		log.Fatal(err)
	}

	// look for silver searcher
	_, err = which("ag")
	if err != nil {
		log.Fatal("the silver search is not installed, stopping\n")
	}

	flag.BoolVar(&verbose_mode, "verbose", false, "enable verbose mode")
	flag.BoolVar(&dry_run_mode, "dry", false, "enable dry_run mode")
	flag.BoolVar(&force_mode, "force", false, "enable force mode")
	flag.Parse()
	if verbose_mode {
		log.Printf("verbose mode: %t", verbose_mode)
		log.Printf("dry_run mode: %t", dry_run_mode)
		log.Printf("force mode: %t", force_mode)
	}
	//
	images, err_images := get_images_from_qrc("seafile-client.qrc")
	if err_images != nil {
		log.Fatal(err)
	}

	for _, image := range images {
		if !check_image_from_src(image, force_mode) {
			log.Printf("unlinking %s", image)
			if !dry_run_mode {
				_, err := os.Stat(image)
				if err != nil {
					log.Println("file %s is not found", image)
				} else {
					err = syscall.Unlink(image)
					if err != nil {
						log.Println("unable to remove file %s", image)
					}
				}
				// TODO remove @2x file as well
			}
		}
	}
	//  # to do: search the images files to match qrc file
}
