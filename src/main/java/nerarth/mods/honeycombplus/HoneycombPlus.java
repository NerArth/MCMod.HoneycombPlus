package nerarth.mods.honeycombplus;

import nerarth.mods.honeycombplus.block.ModBlocks;
import nerarth.mods.honeycombplus.item.ModCreativeTabs;
import nerarth.mods.honeycombplus.item.ModItems;
import net.fabricmc.api.ModInitializer;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public class HoneycombPlus implements ModInitializer {
    public static final String MOD_ID = "honeycombplus";
    public static final Logger LOGGER = LoggerFactory.getLogger(MOD_ID);

    @Override
    public void onInitialize() {
        ModItems.initialize();
        ModBlocks.initialize();
        ModCreativeTabs.initialize();
        LOGGER.info("Honeycomb Plus initialized");
    }
}
