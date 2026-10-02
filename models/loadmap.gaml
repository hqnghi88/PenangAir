/***
* Name: mainroadcells
* Author: minhduc0711
* Description: 
* Tags: Tag1, Tag2, TagN
***/
model main

global {
	string appkey <- "";
	image_file static_map_request;
	string map_center <- "48.8566140,2.3522219";
	int map_zoom <- 16 max: 20 min: 0;
	point map_size <- {1567, 1107};
	//	point map_size <-{200,200};
	action load_map() {
		float s <- world.shape.height / world.shape.width;
		map_size <- {500, 500 * s};
		string
		request <- "https://api.mapbox.com/styles/v1/mapbox/satellite-v9/static/" + "[" + map_center + "]/" + int(map_size.x) + "x" + int(map_size.y) + "@2x?" + "access_token=";
		write "Request : " + request;
		static_map_request <- image_file(request, "JPEG");
	}

	//	shape_file roads_shape_file <- shape_file( "../includes/bigger_map/vnm_rdsl_2015_OSM.shp");
	shape_file roads_shape_file <- shape_file("../includes/bigger_map/hanoi_roads_.shp");
	shape_file buildings_shape_file <- shape_file("../includes/bigger_map/hanoi2.shp");
	geometry shape <- envelope(buildings_shape_file);
	//	list<pollutant_grid> active_cells;
	init {

	//		map answers <- user_input_dialog("Center of the map can be a pair lat,lon (e.g; '48.8566140,2.3522219')", [enter("Center",map_center),enter("Zoom x",map_zoom),enter("Size", map_size)]);
	//	    map_center <- answers["Center"]; 
	//		map_zoom <- int(answers["Zoom x"]);
	//		map_size <- point(answers["Size"]);
	//		point loc<-(world.shape.location CRS_transform("EPSG:4326")).location;
	//		map_center <-""+loc.y+","+loc.x ;
	//		&boundingBox=38.915,-77.072,38.876,-77.001&size=1100,500@2x
	//		point l1<-{2393241.4566,11792211.7398};
	//		point l2<-{2389492.9242,11796892.4212};
	//		l1<-(l1 CRS_transform("EPSG:4326")).location;
	//		l2<-(l2 CRS_transform("EPSG:4326")).location;
	//		map_center <-""+l1.y+","+l1.x+","+l2.y+","+l2.x;
	//	https://air-quality-api.open-meteo.com/v1/air-quality?latitude=20.98776569973214&longitude=105.93916169971295&hourly=pm10,pm2_5
	//20.926528929999986,105.7677002,21.121488569999993,106.02005768
	//21.099234882428494,105.71216583251955,20.96464560107569,105.99266052246094
	//	https://api.waqi.info/v2/map/bounds?token=3e88ec52a139b2da87ef8a5e2215c21ad16ea263&latlng=21.099234882428494,105.71216583251955,20.96464560107569,105.99266052246094
		geometry loc <- (world.shape CRS_transform ("EPSG:4326"));
		map_center <- "" + loc.points[0].y + "," + loc.points[0].x + "," + loc.points[2].y + "," + loc.points[2].x;
		write loc;
		//		map_center <- "105.93916169971295,20.98776569973214,105.94918339971682,20.99437559973104";
		write map_center;
		//		do load_map;
		create road from: roads_shape_file {
		}

		do loadAQ;
		//
		//		create building from: buildings_shape_file {
		//		}
		save road to: "../includes/bigger_map/_roads_.shp" format: "shp" crs: "3857";
	}

	reflex sss when: every(60 #cycle) {
		do loadAQ;
	}

	action loadAQ() {
		ask traffic_incident {
			do die;
		}

		// Open-Meteo CAMS feed (keyless) for the Penang site. Replaces the
		// dead WAQI token URL, which was also hardcoded to Hanoi.
		try {
			json_file
			sss <- json_file("https://air-quality-api.open-meteo.com/v1/air-quality?latitude=5.4096&longitude=100.3161&current=us_aqi,pm2_5&timezone=auto");
			map<string, unknown> c <- sss.contents;
			map<string, unknown> cur <- c["current"];
			if (cur != nil and cur["us_aqi"] != nil) {
				float aqi_val <- float(cur["us_aqi"]);
				point at <- world.shape.location;
				create traffic_incident {
					aqi <- "" + int(aqi_val);
					location <- at;
				}
				write "Penang live US-AQI: " + int(aqi_val);
			}
		}

		catch {
			write "AQI feed unreachable (offline?).";
		}

	}

	action loadtraffic() {
		// Disabled: the Bing Maps key is dead and was hardcoded to Hanoi, and
		// no keyless realtime incident feed exists. Live congestion incidents
		// are now derived from the simulation in traffic2.gaml (api_loader).
		write "loadtraffic: Bing API retired; incidents come from the model.";
	}

}

species traffic_incident {
	geometry shape <- circle(100);
	string aqi;

	aspect default {
		draw shape + 10 color: #red;
		draw "" + aqi at: location color: #pink;
	}

}

species building {
}

species road {

	aspect default {
		draw shape color: #grey;
	}

}

experiment exp {
	float minimum_cycle_duration <- 1.0;
	output {
		display main type: 3d {
			image ("../includes/bigger_map/hanoi.png");
			species traffic_incident position: {0, 0, 0.001};
			//			image static_map_request;
			species road;
		}

	}

}