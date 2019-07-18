package db

import (
	"io"

	"github.com/attic-labs/noms/go/types"

	"github.com/aboodman/replicant/util/jsoms"
)

type CodePut struct {
	InStream io.Reader
	In       struct {
		Origin string
	}
	Out struct {
	}
}

func (c *CodePut) Run(db *DB) error {
	b := types.NewBlob(db.noms, c.InStream)
	return db.SetBundle(b)
	/*
		// TODO: Do we want to validate that it compiles or whatever???
		if b.Equals(db.HeadCommit().Value.Code) {
			return nil
		}

		cc := &CodeExec{}
		cc.In.Origin = c.In.Origin
		cc.In.Name = ".code.put"
		cc.In.Args = jsoms.Value{types.NewList(db.Noms(), b), db.Noms()}

		return cc.Run(db)
	*/
}

type CodeGet struct {
	In struct {
	}
	Out struct {
		OK bool
	}
	OutStream io.Writer
}

func (c *CodeGet) Run(db *DB) error {
	r, err := db.Bundle()
	if err != nil {
		return err
	}
	c.Out.OK = true
	_, err = io.Copy(c.OutStream, r)
	if err != nil {
		return err
	}
	if wc, ok := c.OutStream.(io.WriteCloser); ok {
		err = wc.Close()
		if err != nil {
			return err
		}
	}

	return nil
}

type CodeExec struct {
	In struct {
		Origin string
		Code   jsoms.Hash
		Name   string
		Args   jsoms.Value
	}
	Out struct {
	}
}

func (c *CodeExec) Run(db *DB) (err error) {
	return db.Exec(c.In.Name)
}

/*
func runSystemFunction(ed editor, fn string, args types.List) error {
	switch fn {
	case ".code.put":
		if args.Len() != 1 || args.Get(0).Kind() != types.BlobKind {
			return errors.New("Expected 1 blob argument")
		}
		// TODO: Do we want to validate that it compiles or whatever???
		// TODO: Remove db.PutCode()
		ed.PutCode(args.Get(0).(types.Blob))
		return nil
	default:
		chk.Fail("Unknown system function: %s", fn)
		return nil
	}
}

func isSystemFunction(fn string) bool {
	return fn[0] == '.'
}
*/
