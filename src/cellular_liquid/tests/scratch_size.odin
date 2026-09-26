package cellular_liquid_tests

import liquid ".."
import "core:fmt"
import "core:testing"

@(test)
t_scratch_size :: proc(t: ^testing.T) {
	fmt.println("actual:", size_of(liquid.Liquid_State))
	fmt.println("formula:", 4*liquid.CELL_COUNT + 2*liquid.H_EDGES + 2*liquid.V_EDGES + size_of(i32))
}
