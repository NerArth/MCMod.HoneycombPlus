package nerarth.mods.honeycombplus.mixin;

import com.llamalad7.mixinextras.injector.wrapoperation.Operation;
import com.llamalad7.mixinextras.injector.wrapoperation.WrapOperation;
import nerarth.mods.honeycombplus.item.ModItems;
import net.minecraft.world.entity.animal.golem.CopperGolem;
// import net.minecraft.world.item.Item;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.item.Items;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;

@Mixin(CopperGolem.class)
public abstract class CopperGolemMixin {
    @WrapOperation(
            method = "mobInteract",
            at = @At(
                    value = "INVOKE",
                    target = "Lnet/minecraft/world/item/ItemStack;is(Ljava/lang/Object;)Z"
            )
    )
    private boolean honeycombplus$allowFineWaxOnCopperGolem(ItemStack instance, Object item, Operation<Boolean> original) {
        if (item == Items.HONEYCOMB && instance.is(ModItems.WAX)) {
            return true;
        }
        return original.call(instance, item);
    }
}
