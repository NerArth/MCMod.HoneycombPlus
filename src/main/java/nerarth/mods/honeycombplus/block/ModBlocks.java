package nerarth.mods.honeycombplus.block;

import nerarth.mods.honeycombplus.HoneycombPlus;
import net.fabricmc.fabric.api.object.builder.v1.block.type.BlockSetTypeBuilder;
import net.minecraft.core.Registry;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.core.registries.Registries;
import net.minecraft.resources.Identifier;
import net.minecraft.resources.ResourceKey;
import net.minecraft.world.item.BlockItem;
import net.minecraft.world.item.Item;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.CopperBulbBlock;
import net.minecraft.world.level.block.DoorBlock;
import net.minecraft.world.level.block.IronBarsBlock;
import net.minecraft.world.level.block.LanternBlock;
import net.minecraft.world.level.block.RotatedPillarBlock;
import net.minecraft.world.level.block.SlabBlock;
import net.minecraft.world.level.block.SoundType;
import net.minecraft.world.level.block.StairBlock;
import net.minecraft.world.level.block.TrapDoorBlock;
import net.minecraft.world.level.block.WallBlock;
import net.minecraft.world.level.block.WaterloggedTransparentBlock;
import net.minecraft.world.level.block.state.BlockBehaviour;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.block.state.properties.BlockSetType;
import net.minecraft.world.level.block.state.properties.NoteBlockInstrument;
import net.minecraft.world.level.material.MapColor;
import net.minecraft.world.level.material.PushReaction;

import java.util.function.Function;

public final class ModBlocks {
    public static final BlockSetType HONEYCOMB_SET_TYPE = BlockSetTypeBuilder.copyOf(BlockSetType.BAMBOO)
            .soundType(SoundType.CORAL_BLOCK)
            .register(Identifier.fromNamespaceAndPath(HoneycombPlus.MOD_ID, "honeycomb"));

    // 1. Base Honeycomb Variants (0.6f / 0.6f, hand-harvestable)
    public static final Block HONEYCOMB_STAIRS = register(
            "honeycomb_stairs",
            props -> createStair(Blocks.HONEYCOMB_BLOCK.defaultBlockState(), props),
            baseHoneycombProps()
    );
    public static final Block HONEYCOMB_SLAB = register(
            "honeycomb_slab",
            SlabBlock::new,
            baseHoneycombProps()
    );
    public static final Block HONEYCOMB_WALL = register(
            "honeycomb_wall",
            WallBlock::new,
            baseHoneycombProps().forceSolidOn()
    );

    // 2. Polished Honeycomb Set (1.5f / 1.5f, requires pickaxe)
    public static final Block POLISHED_HONEYCOMB = register(
            "polished_honeycomb",
            Block::new,
            polishedOrCutProps()
    );
    public static final Block POLISHED_HONEYCOMB_STAIRS = register(
            "polished_honeycomb_stairs",
            props -> createStair(POLISHED_HONEYCOMB.defaultBlockState(), props),
            polishedOrCutProps()
    );
    public static final Block POLISHED_HONEYCOMB_SLAB = register(
            "polished_honeycomb_slab",
            SlabBlock::new,
            polishedOrCutProps()
    );
    public static final Block POLISHED_HONEYCOMB_WALL = register(
            "polished_honeycomb_wall",
            WallBlock::new,
            polishedOrCutProps().forceSolidOn()
    );

    // 3. Cut Honeycomb Set (1.5f / 1.5f, requires pickaxe)
    public static final Block CUT_HONEYCOMB = register(
            "cut_honeycomb",
            Block::new,
            polishedOrCutProps()
    );
    public static final Block CUT_HONEYCOMB_STAIRS = register(
            "cut_honeycomb_stairs",
            props -> createStair(CUT_HONEYCOMB.defaultBlockState(), props),
            polishedOrCutProps()
    );
    public static final Block CUT_HONEYCOMB_SLAB = register(
            "cut_honeycomb_slab",
            SlabBlock::new,
            polishedOrCutProps()
    );
    public static final Block CUT_HONEYCOMB_WALL = register(
            "cut_honeycomb_wall",
            WallBlock::new,
            polishedOrCutProps().forceSolidOn()
    );

    // 4. Honeycomb Bricks Set (1.5f / 3.0f, requires pickaxe)
    public static final Block HONEYCOMB_BRICKS = register(
            "honeycomb_bricks",
            Block::new,
            brickOrSculptedProps()
    );
    public static final Block HONEYCOMB_BRICK_STAIRS = register(
            "honeycomb_brick_stairs",
            props -> createStair(HONEYCOMB_BRICKS.defaultBlockState(), props),
            brickOrSculptedProps()
    );
    public static final Block HONEYCOMB_BRICK_SLAB = register(
            "honeycomb_brick_slab",
            SlabBlock::new,
            brickOrSculptedProps()
    );
    public static final Block HONEYCOMB_BRICK_WALL = register(
            "honeycomb_brick_wall",
            WallBlock::new,
            brickOrSculptedProps().forceSolidOn()
    );

    // 5. Sculpted Honeycomb (1.5f / 3.0f, requires pickaxe)
    public static final Block CHISELED_HONEYCOMB = register(
            "chiseled_honeycomb",
            Block::new,
            brickOrSculptedProps()
    );
    public static final Block HONEYCOMB_PILLAR = register(
            "honeycomb_pillar",
            RotatedPillarBlock::new,
            brickOrSculptedProps()
    );

    // 6. Lattice Blocks (1.5f / 1.5f, requires pickaxe)
    public static final Block HONEYCOMB_GRATE = register(
            "honeycomb_grate",
            ModBlocks::createGrate,
            polishedOrCutProps()
                    .noOcclusion()
                    .isValidSpawn((state, level, pos, type) -> false)
                    .isRedstoneConductor((state, level, pos) -> false)
                    .isSuffocating((state, level, pos) -> false)
                    .isViewBlocking((state, level, pos, aabb) -> false)
    );
    public static final Block HONEYCOMB_BARS = register(
            "honeycomb_bars",
            ModBlocks::createBars,
            polishedOrCutProps().noOcclusion()
    );

    // 7. Doors & Trapdoors (1.2f / 1.5f, hand-harvestable)
    public static final Block HONEYCOMB_DOOR = register(
            "honeycomb_door",
            props -> new DoorBlock(HONEYCOMB_SET_TYPE, props) {},
            BlockBehaviour.Properties.of()
                    .mapColor(MapColor.COLOR_ORANGE)
                    .instrument(NoteBlockInstrument.FLUTE)
                    .strength(1.2F, 1.5F)
                    .sound(SoundType.CORAL_BLOCK)
                    .noOcclusion()
                    .pushReaction(PushReaction.POPPED)
    );
    public static final Block HONEYCOMB_TRAPDOOR = register(
            "honeycomb_trapdoor",
            props -> new TrapDoorBlock(HONEYCOMB_SET_TYPE, props) {},
            BlockBehaviour.Properties.of()
                    .mapColor(MapColor.COLOR_ORANGE)
                    .instrument(NoteBlockInstrument.FLUTE)
                    .strength(1.2F, 1.5F)
                    .sound(SoundType.CORAL_BLOCK)
                    .noOcclusion()
                    .isValidSpawn((state, level, pos, type) -> false)
    );

    // 8. Honeyed Glass & Pane (0.8f / 0.8f, always hand-harvestable, sticky slide + fall reduction + movement drag)
    public static final Block HONEYED_GLASS = register(
            "honeyed_glass",
            HoneyedGlassBlock::new,
            BlockBehaviour.Properties.of()
                    .mapColor(MapColor.COLOR_ORANGE)
                    .strength(0.8F, 0.8F)
                    .speedFactor(0.4F)
                    .jumpFactor(0.5F)
                    .noOcclusion()
                    .sound(SoundType.HONEY_BLOCK)
                    .isValidSpawn((state, level, pos, type) -> false)
                    .isRedstoneConductor((state, level, pos) -> false)
                    .isSuffocating((state, level, pos) -> false)
                    .isViewBlocking((state, level, pos, aabb) -> false)
    );
    public static final Block HONEYED_GLASS_PANE = register(
            "honeyed_glass_pane",
            HoneyedGlassPaneBlock::new,
            BlockBehaviour.Properties.of()
                    .mapColor(MapColor.COLOR_ORANGE)
                    .strength(0.8F, 0.8F)
                    .speedFactor(0.4F)
                    .jumpFactor(0.5F)
                    .noOcclusion()
                    .sound(SoundType.HONEY_BLOCK)
    );

    // 9. Lighting Blocks
    public static final Block HONEYCOMB_LANTERN = register(
            "honeycomb_lantern",
            LanternBlock::new,
            BlockBehaviour.Properties.of()
                    .mapColor(MapColor.COLOR_ORANGE)
                    .forceSolidOn()
                    .requiresCorrectToolForDrops()
                    .strength(1.5F, 1.5F)
                    .sound(SoundType.LANTERN)
                    .lightLevel(state -> 15)
                    .noOcclusion()
                    .pushReaction(PushReaction.POPPED)
    );
    public static final Block HONEYCOMB_LAMP = register(
            "honeycomb_lamp",
            CopperBulbBlock::new,
            BlockBehaviour.Properties.of()
                    .mapColor(MapColor.COLOR_ORANGE)
                    .instrument(NoteBlockInstrument.FLUTE)
                    .requiresCorrectToolForDrops()
                    .strength(1.5F, 2.0F)
                    .sound(SoundType.COPPER_BULB)
                    .isRedstoneConductor((state, level, pos) -> false)
                    .lightLevel(state -> state.getValue(CopperBulbBlock.LIT) ? 15 : 0)
    );

    private ModBlocks() {
    }

    private static BlockBehaviour.Properties baseHoneycombProps() {
        return BlockBehaviour.Properties.of()
                .mapColor(MapColor.COLOR_ORANGE)
                .instrument(NoteBlockInstrument.FLUTE)
                .strength(0.6F, 0.6F)
                .sound(SoundType.CORAL_BLOCK);
    }

    private static BlockBehaviour.Properties polishedOrCutProps() {
        return BlockBehaviour.Properties.of()
                .mapColor(MapColor.COLOR_ORANGE)
                .instrument(NoteBlockInstrument.FLUTE)
                .requiresCorrectToolForDrops()
                .strength(1.5F, 1.5F)
                .sound(SoundType.CORAL_BLOCK);
    }

    private static BlockBehaviour.Properties brickOrSculptedProps() {
        return BlockBehaviour.Properties.of()
                .mapColor(MapColor.COLOR_ORANGE)
                .instrument(NoteBlockInstrument.FLUTE)
                .requiresCorrectToolForDrops()
                .strength(1.5F, 3.0F)
                .sound(SoundType.CORAL_BLOCK);
    }

    private static StairBlock createStair(BlockState baseState, BlockBehaviour.Properties props) {
        return new StairBlock(baseState, props) {};
    }

    private static WaterloggedTransparentBlock createGrate(BlockBehaviour.Properties props) {
        return new WaterloggedTransparentBlock(props) {};
    }

    private static IronBarsBlock createBars(BlockBehaviour.Properties props) {
        return new IronBarsBlock(props) {};
    }

    private static Block register(String name, Function<BlockBehaviour.Properties, Block> factory, BlockBehaviour.Properties properties) {
        Identifier id = Identifier.fromNamespaceAndPath(HoneycombPlus.MOD_ID, name);
        ResourceKey<Block> blockKey = ResourceKey.create(Registries.BLOCK, id);
        Block block = factory.apply(properties.setId(blockKey));
        Registry.register(BuiltInRegistries.BLOCK, blockKey, block);

        ResourceKey<Item> itemKey = ResourceKey.create(Registries.ITEM, id);
        BlockItem blockItem = new BlockItem(block, new Item.Properties().setId(itemKey).useBlockDescriptionPrefix());
        Registry.register(BuiltInRegistries.ITEM, itemKey, blockItem);

        return block;
    }

    public static void initialize() {
        // Trigger static field initialization
    }
}
