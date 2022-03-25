# ``Saga/Writer``

Writers turn an ``ItemRenderingContext`` into a `String`, which Saga can write to files.


## Overview
These writers expect to be given a function that can turn an ``ItemRenderingContext`` (which holds the ``Item`` among other things) into a `String`, which it'll then write to disk, to the `output` folder. To turn an ``Item`` into a HTML `String`, you'll want to use a template language or a HTML DSL, such as [SagaSwimRenderer](https://github.com/loopwerk/SagaSwimRenderer) or [SagaStencilRenderer](https://github.com/loopwerk/SagaStencilRenderer).

Saga does not come bundled with any writers out of the box.
