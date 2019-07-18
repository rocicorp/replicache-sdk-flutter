package exec

import (
	"bytes"
	"fmt"
	"io"
	"strings"

	"github.com/attic-labs/noms/go/types"
	jn "github.com/attic-labs/noms/go/util/json"
	o "github.com/robertkrimen/otto"

	"github.com/aboodman/replicant/util/chk"
)

const (
	cmdPut int = iota
	cmdHas
	cmdGet
)

type Database interface {
	Put(id string, value types.Value) error
	Has(id string) (ok bool, err error)
	Get(id string) (types.Value, error)
}

func Run(db Database, source io.Reader, fn string, args types.List) error {
	vm := o.New()

	_, err := vm.Run(bootstrap)
	chk.NoError(err)

	_, err = vm.Run(source)
	if err != nil {
		return fmt.Errorf("Error loading code bundle: %s", err.Error())
	}

	vm.Set("send", func(call o.FunctionCall) o.Value {
		args := call.ArgumentList
		cmdID, err := args[0].ToInteger()
		chk.NoError(err)

		res, err := vm.Object("({})")
		chk.NoError(err)

		switch int(cmdID) {
		case cmdPut:
			err = db.Put(args[1].String(), strings.NewReader(args[2].String()))
			if err != nil {
				res.Set("error", err.Error())
			}

		case cmdHas:
			ok, err := db.Has(args[1].String())
			if err != nil {
				res.Set("error", err.Error())
			} else {
				res.Set("ok", ok)
			}

		case cmdGet:
			sb := &strings.Builder{}
			ok, err := db.Get(args[1].String(), sb)
			if err != nil {
				res.Set("error", err.Error())
			} else {
				res.Set("ok", ok)
				res.Set("data", sb.String())
			}
		}
		return res.Value()
	})

	f, err := vm.Get("recv")
	chk.NoError(err)
	chk.NotNil(f)

	buf := &bytes.Buffer{}
	err = jn.ToJSON(args, buf, jn.ToOptions{
		Lists: true,
		Maps:  true,
	})
	if err != nil {
		return err
	}

	_, err = f.Call(o.NullValue(), fn, string(buf.Bytes()))
	return err
}
