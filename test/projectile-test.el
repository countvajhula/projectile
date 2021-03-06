;;; projectile-test.el

;; Copyright © 2018 Bozhidar Batsov

;; Author: Bozhidar Batsov <bozhidar@batsov.com>

;; This file is NOT part of GNU Emacs.

;; This program is free software: you can redistribute it and/or
;; modify it under the terms of the GNU General Public License as
;; published by the Free Software Foundation, either version 3 of the
;; License, or (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful, but
;; WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;; General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see `http://www.gnu.org/licenses/'.

;;; Commentary:

;; This file is part of Projectile.

;;; Code:

(require 'projectile)
(require 'buttercup)

;;; Test Utilities
(defmacro projectile-test-with-sandbox (&rest body)
  "Evaluate BODY in an empty temporary directory."
  (declare (indent 0) (debug (&rest form)))
  `(let ((sandbox (expand-file-name
                   (convert-standard-filename "test/sandbox/")
                   (file-name-directory (locate-library "projectile.el" t)))))
     (when (file-directory-p sandbox)
       (delete-directory sandbox t))
     (make-directory sandbox t)
     (let ((default-directory sandbox))
       ,@body)))

(defmacro projectile-test-with-files (files &rest body)
  "Evaluate BODY in the presence of FILES.

You'd normally combine this with `projectile-test-with-sandbox'."
  (declare (indent 1) (debug (sexp &rest form)))
  `(progn
     ,@(mapcar (lambda (file)
                 (if (string-suffix-p "/" file)
                     `(make-directory ,file t)
                   `(with-temp-file ,file)))
               files)
     ,@body))

(defun projectile-test-tmp-file-path ()
  "Return a filename suitable to save data to in the
test temp directory"
  (concat projectile-test-path
          "/tmp/temporary-file-" (format "%d" (random))
          ".eld"))

;;; Tests
(describe "projectile-project-name"
  (it "return projectile-project-name when present"
    (let ((projectile-project-name "name"))
      (expect (projectile-project-name) :to-equal "name")
      (expect (projectile-project-name "other") :to-equal "name")))
  (it "uses projectile-project-name-function to get the project name from the project dir"
    (let ((projectile-project-name-function (lambda (dir) dir)))
      (expect (projectile-project-name "some/dir") :to-equal "some/dir")))
  (it "acts on the current project is not passed a project dir explicitly"
    (spy-on 'projectile-project-root :and-return-value "current/project")
    (let ((projectile-project-name-function (lambda (dir) dir)))
      (expect (projectile-project-name) :to-equal "current/project"))))

(describe "projectile-prepend-project-name"
  (it "prepends the project name to its parameter"
    (spy-on 'projectile-project-name :and-return-value "project")
    (expect (projectile-prepend-project-name "Test") :to-equal "[project] Test")))

(describe "projectile-expand-root"
  (it "expands a relative path into an absolute path within a project"
    (spy-on  'projectile-project-root :and-return-value "/path/to/project")
    (expect (projectile-expand-root "foo") :to-equal "/path/to/project/foo")
    (expect (projectile-expand-root "foo/bar") :to-equal "/path/to/project/foo/bar")
    (expect (projectile-expand-root "./foo/bar") :to-equal "/path/to/project/foo/bar")))

(describe "projectile-register-project-type"
  (it "prepends new projects to projectile-project-types"
    (projectile-register-project-type 'foo '("Foo"))
    (expect (caar projectile-project-types) :to-equal 'foo)
    (projectile-register-project-type 'bar '("Bar"))
    (expect (caar projectile-project-types) :to-equal 'bar)))

(describe "projectile-project-type"
  (it "detects the type of Projectile's project"
    (expect (projectile-project-type) :to-equal 'emacs-cask))
  (it "caches the project type"
    (expect (gethash (projectile-project-root) projectile-project-type-cache) :to-equal 'emacs-cask)))

(describe "projectile-detect-project-type"
  (it "detects project-type for rails-like npm tests"
    (projectile-test-with-sandbox
     (projectile-test-with-files
      ("project/"
       "project/Gemfile"
       "project/app/"
       "project/lib/"
       "project/db/"
       "project/config/"
       "project/spec/"
       "project/package.json")
      (let ((projectile-indexing-method 'native))
        (spy-on 'projectile-project-root :and-return-value (file-truename (expand-file-name "project/")))
        (expect (projectile-detect-project-type) :to-equal 'rails-rspec))))))

(describe "projectile-dirname-matching-count"
  (it "counts matching dirnames ascending file paths"
    (expect (projectile-dirname-matching-count "src/food/sea.c" "src/food/cat.c") :to-equal 2)
    (expect (projectile-dirname-matching-count "src/weed/sea.c" "src/food/sea.c") :to-equal 0)
    (expect (projectile-dirname-matching-count "test/demo-test.el" "demo.el") :to-equal 0)))

(describe "projectile-find-matching-test"
  (it "finds matching test or file"
    (projectile-test-with-sandbox
     (projectile-test-with-files
      ("project/app/models/weed/"
       "project/app/models/food/"
       "project/spec/models/weed/"
       "project/spec/models/food/"
       "project/app/models/weed/sea.rb"
       "project/app/models/food/sea.rb"
       "project/spec/models/weed/sea_spec.rb"
       "project/spec/models/food/sea_spec.rb")
      (let ((projectile-indexing-method 'native))
        (spy-on 'projectile-project-type :and-return-value 'rails-rspec)
        (spy-on 'projectile-project-root :and-return-value (file-truename (expand-file-name "project/")))
        (expect (projectile-find-matching-test "app/models/food/sea.rb") :to-equal "spec/models/food/sea_spec.rb")
        (expect (projectile-find-matching-file "spec/models/food/sea_spec.rb") :to-equal "app/models/food/sea.rb")))))
  (it "finds matching test or file in a custom project"
    (projectile-test-with-sandbox
     (projectile-test-with-files
      ("project/src/foo/"
       "project/src/bar/"
       "project/test/foo/"
       "project/test/bar/"
       "project/src/foo/foo.service.js"
       "project/src/bar/bar.service.js"
       "project/test/foo/foo.service.spec.js"
       "project/test/bar/bar.service.spec.js")
      (let ((projectile-indexing-method 'native))
        (projectile-register-project-type 'npm-project '("somefile") :test-suffix ".spec")
        (spy-on 'projectile-project-type :and-return-value 'npm-project)
        (spy-on 'projectile-project-root :and-return-value (file-truename (expand-file-name "project/")))
        (expect (projectile-find-matching-test "src/foo/foo.service.js") :to-equal "test/foo/foo.service.spec.js")
        (expect (projectile-find-matching-file "test/bar/bar.service.spec.js") :to-equal "src/bar/bar.service.js")))))
  (it "finds matching test or file in a custom project with dirs"
    (projectile-test-with-sandbox
     (projectile-test-with-files
      ("project/source/foo/"
       "project/source/bar/"
       "project/spec/foo/"
       "project/spec/bar/"
       "project/source/foo/foo.service.js"
       "project/source/bar/bar.service.js"
       "project/spec/foo/foo.service.spec.js"
       "project/spec/bar/bar.service.spec.js")
      (let ((projectile-indexing-method 'native))
        (projectile-register-project-type 'npm-project '("somefile")
                                          :test-suffix ".spec"
                                          :test-dir "spec/"
                                          :src-dir "source/")
        (spy-on 'projectile-project-type :and-return-value 'npm-project)
        (spy-on 'projectile-project-root :and-return-value (file-truename (expand-file-name "project/")))
        (expect (projectile-find-matching-test "source/foo/foo.service.js") :to-equal "spec/foo/foo.service.spec.js")
        (expect (projectile-find-matching-file "spec/bar/bar.service.spec.js") :to-equal "source/bar/bar.service.js"))))))

(describe "projectile-get-all-sub-projects"
  (it "excludes out-of-project submodules"
    (projectile-test-with-sandbox
     (projectile-test-with-files
      (;; VCS root is here
       "project/"
       "project/.git/"
       "project/.gitmodules"
       ;; Current project root is here:
       "project/web-ui/"
       "project/web-ui/.projectile"
       ;; VCS git submodule will return the following submodules,
       ;; relative to current project root, 'project/web-ui/':
       "project/web-ui/vendor/client-submodule/"
       "project/server/vendor/server-submodule/")
      (let ((project (file-truename (expand-file-name "project/web-ui"))))
        (spy-on 'projectile-files-via-ext-command :and-call-fake
                (lambda (dir vcs)
                  (when (string= dir project)
                    '("vendor/client-submodule"
                      "../server/vendor/server-submodule"))))
        (spy-on 'projectile-project-root :and-return-value project)
        ;; assert that it only returns the submodule 'project/web-ui/vendor/client-submodule/'
        (expect (projectile-get-all-sub-projects project) :to-equal
                (list (expand-file-name "vendor/client-submodule/" project))))))))

(describe "projectile-configure-command"
  (it "configure command for generic project type"
    (spy-on 'projectile-default-configure-command :and-return-value nil)
    (spy-on 'projectile-project-type :and-return-value 'generic)
    (expect (projectile-configure-command "fsdf") :to-equal nil)))

;;; known projects tests

(describe "projectile-add-known-project"
  :var (projectile-known-projects-file)
  (before-each
   (setq projectile-known-projects-file (projectile-test-tmp-file-path)))

  (after-each
   (delete-file projectile-known-projects-file nil))

  (it "an added project should be added to the list of known projects"
    (let ((projectile-known-projects nil))
      (projectile-add-known-project "~/my/new/project/")
      (expect projectile-known-projects :to-equal '("~/my/new/project/"))))
  (it "adding a project should move it to the front of the list of known projects, if it already existed."
    (let ((projectile-known-projects '("~/b/" "~/a/")))
      (projectile-add-known-project "~/a/")
      (expect projectile-known-projects :to-equal '("~/a/" "~/b/"))))
  (it "~/project and ~/project/ should not be added separately to the known projects list"
    (let ((projectile-known-projects '("~/project/")))
      (projectile-add-known-project "~/project")
      (expect projectile-known-projects :to-equal '("~/project/"))
      (projectile-add-known-project "~/b")
      (projectile-add-known-project "~/b/")
      (expect projectile-known-projects :to-equal '("~/b/" "~/project/")))))

(describe "projectile-load-known-projects"
  (it "loads known projects through serialization functions"
    (let ((projectile-known-projects-file (projectile-test-tmp-file-path)))
      (spy-on 'projectile-unserialize :and-return-value '("a1" "a2"))
      (projectile-load-known-projects)
      (expect 'projectile-unserialize :to-have-been-called-with projectile-known-projects-file)
      (expect projectile-known-projects :to-equal '("a1" "a2")))))

(describe "projectile-merge-known-projects"
  (it "merges known projects"
    (let ((projectile-known-projects nil)
          (projectile-known-projects-file (projectile-test-tmp-file-path)))
      ;; initialize saved known projects and load it from disk
      (projectile-serialize '("a1" "a2" "a3" "a4" "a5")
                            projectile-known-projects-file)
      (projectile-load-known-projects)
      ;; simulate other emacs session changes by: remove a2 a5 and adding b1 b2
      (projectile-serialize '("a3" "b1" "a1" "a4" "b2")
                            projectile-known-projects-file)
      ;; remove a4 and add a6 and merge with disk
      (setq projectile-known-projects '("a6" "a1" "a2" "a3" "a5"))
      (projectile-merge-known-projects)
      (delete-file projectile-known-projects-file nil)
      (expect projectile-known-projects :to-equal '("a6" "a1" "a3" "b1" "b2"))))
  (it "merges known projects to an empty file"
    (let ((projectile-known-projects nil)
          (projectile-known-projects-file (projectile-test-tmp-file-path)))
      ;; initialize saved known projects and load it from disk
      (projectile-serialize '("a1" "a2" "a3" "a4" "a5")
                            projectile-known-projects-file)
      (projectile-load-known-projects)
      ;; empty the on disk known projects list
      (projectile-serialize '() projectile-known-projects-file)
      ;; merge
      (projectile-merge-known-projects)
      (delete-file projectile-known-projects-file nil)
      (expect projectile-known-projects :to-equal '())))
  (it "merges known projects from an empty file"
    (let ((projectile-known-projects nil)
          (projectile-known-projects-file (projectile-test-tmp-file-path)))
      ;; initialize saved known projects and load it from disk
      (projectile-serialize '() projectile-known-projects-file)
      (projectile-load-known-projects)
      ;; empty the on disk known projects list
      (projectile-serialize '("a" "b" "c" "d") projectile-known-projects-file)
      ;; merge
      (projectile-merge-known-projects)
      (delete-file projectile-known-projects-file nil)
      (expect projectile-known-projects :to-equal '("a" "b" "c" "d"))))
  (it "merges known projects while keeping their order"
    (let ((projectile-known-projects nil)
          (projectile-known-projects-file (projectile-test-tmp-file-path)))
      ;; initialize saved known projects and load it from disk
      (projectile-serialize '("a" "b" "c" "d") projectile-known-projects-file)
      (projectile-load-known-projects)
      ;; save the same list in different order
      (projectile-serialize '("d" "c" "b" "a") projectile-known-projects-file)
      ;; merge
      (projectile-merge-known-projects)
      (delete-file projectile-known-projects-file nil)
      (expect projectile-known-projects :to-equal '("a" "b" "c" "d")))))

(describe "projectile-save-known-projects"
  (it "saves known projects through serialization functions"
    (let ((projectile-known-projects-file (projectile-test-tmp-file-path))
          (projectile-known-projects '(floop)))
      (spy-on 'projectile-serialize)
      (projectile-save-known-projects)
      (expect 'projectile-serialize :to-have-been-called-with '(floop) projectile-known-projects-file))))

(describe "projectile-serialization-functions"
  (it "tests that serialization functions can save/restore data to the filesystem"
    (let ((this-test-file (projectile-test-tmp-file-path)))
      (unwind-protect
        (progn
          (projectile-serialize '(some random data) this-test-file)
          (expect (projectile-unserialize this-test-file) :to-equal '(some random data))
          (when (file-exists-p this-test-file)
            (delete-file this-test-file)))))))

(describe "projectile-clear-known-projects"
  (it "clears known projects"
    (let ((projectile-known-projects '("one" "two" "three"))
          (projectile-known-projects-file (projectile-test-tmp-file-path)))
      (projectile-clear-known-projects)
      (expect projectile-known-projects :to-equal nil))))

(describe "projectile-test-ignored-directory-p"
  (it "ignores specified literal directory values"
    (spy-on 'projectile-ignored-directories :and-return-value '("/path/to/project/tmp"))
    (expect (projectile-ignored-directory-p "/path/to/project/tmp") :to-be-truthy)
    (expect (projectile-ignored-directory-p "/path/to/project/log") :not :to-be-truthy))
  (it "ignores specified regex directory values"
    (spy-on 'projectile-ignored-directories :and-return-value '("/path/to/project/t\\.*"))
    (expect (projectile-ignored-directory-p "/path/to/project/tmp") :to-be-truthy)
    (expect (projectile-ignored-directory-p "/path/to/project/log") :not :to-be-truthy)))

(describe "projectile-relevant-known-projects"
  :var 'known-projects
  (before-all
    (setq known-projects '("~/foo/" "~/bar/" "~/baz/")))

  (describe "when projectile-current-project-on-switch is 'remove"
    (it "removes the current project"
      (spy-on 'projectile-project-root :and-return-value "~/foo/")
      (let ((projectile-current-project-on-switch 'remove)
            (projectile-known-projects known-projects))
        (expect (projectile-relevant-known-projects) :to-equal '("~/bar/" "~/baz/")))))

  (describe "when projectile-current-project-on-switch is 'move-to-end"
    (it "moves the current project to the end of projectile-known-projects"
      (spy-on 'projectile-project-root :and-return-value "~/foo/")
      (let ((projectile-current-project-on-switch 'move-to-end)
            (projectile-known-projects known-projects))
        (expect (projectile-relevant-known-projects) :to-equal '("~/bar/" "~/baz/" "~/foo/")))))

  (describe "when projectile-current-project-on-switch is 'keep"
    (it "returns projectile-known-projects"
      (spy-on 'projectile-project-root :and-return-value "~/foo/")
      (let ((projectile-current-project-on-switch 'keep)
            (projectile-known-projects known-projects))
        (expect (projectile-relevant-known-projects) :to-equal '("~/foo/" "~/bar/" "~/baz/"))))))

(describe "projectile-relevant-open-projects"
  (describe "when projectile-current-project-on-switch is 'remove"
    (it "removes the current project"
      (spy-on 'projectile-open-projects :and-return-value '("~/foo/" "~/bar/" "~/baz/"))
      (spy-on 'projectile-project-root :and-return-value "~/foo/")
      (let ((projectile-current-project-on-switch 'remove))
        (expect (projectile-relevant-open-projects) :to-equal '("~/bar/" "~/baz/")))))

  (describe "when projectile-current-project-on-switch is 'move-to-end"
    (it "moves the current project to the end of projectile-known-projects"
      (spy-on 'projectile-open-projects :and-return-value '("~/foo/" "~/bar/" "~/baz/"))
      (spy-on 'projectile-project-root :and-return-value "~/foo/")
      (let ((projectile-current-project-on-switch 'move-to-end))
        (expect (projectile-relevant-open-projects) :to-equal '("~/bar/" "~/baz/" "~/foo/")))))

  (describe "when projectile-current-project-on-switch is 'keep"
    (it "returns projectile-open-projects"
      (spy-on 'projectile-project-root :and-return-value "~/foo/")
      (spy-on 'projectile-open-projects :and-return-value '("~/foo/" "~/bar/" "~/baz/"))
      (let ((projectile-current-project-on-switch 'keep))
        (expect (projectile-relevant-open-projects) :to-equal '("~/foo/" "~/bar/" "~/baz/"))))))


;;; Mode line tests
(describe "projectile-default-mode-line"
  (it "includes the project name and type when in a project"
    (spy-on 'projectile-project-name :and-return-value "foo")
    (spy-on 'projectile-project-type :and-return-value "bar")
    (expect (projectile-default-mode-line) :to-equal " Projectile[foo:bar]"))
  (it "returns also a - if called outside a project"
    (spy-on 'projectile-project-name :and-return-value nil)
    (spy-on 'projectile-project-type :and-return-value nil)
    (expect (projectile-default-mode-line) :to-equal " Projectile[-]"))
  (it "respects the value of projectile-mode-line-prefix"
    (spy-on 'projectile-project-name :and-return-value "foo")
    (spy-on 'projectile-project-type :and-return-value "bar")
    (let ((projectile-mode-line-prefix " Pro"))
      (expect (projectile-default-mode-line) :to-equal " Pro[foo:bar]"))))
