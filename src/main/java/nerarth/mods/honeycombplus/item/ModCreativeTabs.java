package nerarth.mods.honeycombplus.item;

import nerarth.mods.honeycombplus.HoneycombPlus;
import nerarth.mods.honeycombplus.block.ModBlocks;
import net.fabricmc.fabric.api.creativetab.v1.FabricCreativeModeTab;
import net.minecraft.core.Registry;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.core.registries.Registries;
import net.minecraft.network.chat.Component;
import net.minecraft.resources.Identifier;
import net.minecraft.resources.ResourceKey;
import net.minecraft.world.item.CreativeModeTab;
import net.minecraft.world.item.ItemStack;

public final class ModCreativeTabs {
    public static final ResourceKey<CreativeModeTab> HONEYCOMB_PLUS_TAB_KEY = ResourceKey.create(
            Registries.CREATIVE_MODE_TAB,
            Identifier.fromNamespaceAndPath(HoneycombPlus.MOD_ID, "honeycomb_plus")
    );

    public static final CreativeModeTab HONEYCOMB_PLUS_TAB = Registry.register(
            BuiltInRegistries.CREATIVE_MODE_TAB,
            HONEYCOMB_PLUS_TAB_KEY,
            FabricCreativeModeTab.builder()
                    .title(Component.translatable("itemGroup.honeycombplus.honeycomb_plus"))
                    .icon(() -> new ItemStack(ModBlocks.HONEYCOMB_LANTERN))
                    .displayItems((parameters, output) -> {
                        // Refined Materials
                        output.accept(ModItems.WAX);

                        // Base Honeycomb variants
                        output.accept(ModBlocks.HONEYCOMB_STAIRS);
                        output.accept(ModBlocks.HONEYCOMB_SLAB);
                        output.accept(ModBlocks.HONEYCOMB_WALL);

                        // Polished Honeycomb set
                        output.accept(ModBlocks.POLISHED_HONEYCOMB);
                        output.accept(ModBlocks.POLISHED_HONEYCOMB_STAIRS);
                        output.accept(ModBlocks.POLISHED_HONEYCOMB_SLAB);
                        output.accept(ModBlocks.POLISHED_HONEYCOMB_WALL);

                        // Cut Honeycomb set
                        output.accept(ModBlocks.CUT_HONEYCOMB);
                        output.accept(ModBlocks.CUT_HONEYCOMB_STAIRS);
                        output.accept(ModBlocks.CUT_HONEYCOMB_SLAB);
                        output.accept(ModBlocks.CUT_HONEYCOMB_WALL);

                        // Honeycomb Bricks set
                        output.accept(ModBlocks.HONEYCOMB_BRICKS);
                        output.accept(ModBlocks.HONEYCOMB_BRICK_STAIRS);
                        output.accept(ModBlocks.HONEYCOMB_BRICK_SLAB);
                        output.accept(ModBlocks.HONEYCOMB_BRICK_WALL);

                        // Sculpted Honeycomb
                        output.accept(ModBlocks.CHISELED_HONEYCOMB);
                        output.accept(ModBlocks.HONEYCOMB_PILLAR);

                        // Lattice blocks
                        output.accept(ModBlocks.HONEYCOMB_GRATE);
                        output.accept(ModBlocks.HONEYCOMB_BARS);

                        // Doors & Trapdoors
                        output.accept(ModBlocks.HONEYCOMB_DOOR);
                        output.accept(ModBlocks.HONEYCOMB_TRAPDOOR);

                        // Sticky Glass
                        output.accept(ModBlocks.HONEYED_GLASS);
                        output.accept(ModBlocks.HONEYED_GLASS_PANE);

                        // Lighting
                        output.accept(ModBlocks.HONEYCOMB_LANTERN);
                        output.accept(ModBlocks.HONEYCOMB_LAMP);
                    })
                    .build()
    );

    private ModCreativeTabs() {
    }

    public static void initialize() {
        // Trigger static field initialization
    }
}
