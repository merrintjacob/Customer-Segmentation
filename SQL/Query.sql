
WITH filtered_users AS (
    SELECT
        user_id
    FROM
        sessions
    WHERE 
       session_start > '2023-01-04'
     --flight_booked = 'true' OR hotel_booked = 'true'
    GROUP BY
        user_id
    HAVING 
        COUNT(session_id) > 7
),

session_level AS (
    SELECT
        u.user_id,
        s.session_id,
        s.trip_id,
        u.birthdate,
        EXTRACT(YEAR FROM AGE(u.birthdate)) AS age,
        u.gender,
        u.married,
        u.has_children,
        u.home_country,
        u.home_city,
        u.home_airport,
        u.home_airport_lat,
        u.home_airport_lon,
        u.sign_up_date,
        
        s.session_start,
        s.session_end,
        (EXTRACT(EPOCH FROM (s.session_end - s.session_start))) AS session_duration_in_seconds,
        s.flight_discount,
        s.hotel_discount,
        s.flight_discount_amount,
        s.hotel_discount_amount,
        s.flight_booked,
        s.hotel_booked,
        s.page_clicks,
        s.cancellation,
        
        h.hotel_name,
        CASE 
            WHEN h.nights < 0 THEN ABS(h.nights)
            WHEN h.nights = 0 THEN 1
            ELSE h.nights
        END AS nights,
        h.rooms,
        -- h.check_in_time,
        CASE
            WHEN h.check_in_time > h.check_out_time THEN h.check_out_time
            ELSE h.check_in_time
        END AS check_in_time,  
        -- h.check_out_time,
        CASE 
            WHEN h.check_out_time < h.check_in_time THEN h.check_in_time
            ELSE h.check_out_time
        END AS check_out_time,
        h.hotel_per_room_usd,
        
        f.origin_airport,
        f.destination,
        f.destination_airport,
        f.seats,
        f.return_flight_booked,
        f.departure_time,
  			EXTRACT(MONTH FROM departure_time) AS departure_month,
        f.return_time,
        f.checked_bags,
        f.trip_airline,
        f.destination_airport_lat,
        f.destination_airport_lon,
        f.base_fare_usd

    FROM 
        filtered_users AS fs
    JOIN 
        users AS u ON fs.user_id = u.user_id
    LEFT JOIN
        sessions AS s ON s.user_id = fs.user_id
    LEFT JOIN 
        hotels AS h ON s.trip_id = h.trip_id
    LEFT JOIN 
        flights AS f ON s.trip_id = f.trip_id

    -- s.flight_booked = 'true' OR s.hotel_booked = 'true'
    ORDER BY 
        u.user_id ASC
    -- LIMIT 100
),

trip_level AS (

SELECT 	 user_id,
  			 COUNT(trip_id) AS total_trips,
  			 SUM(CASE WHEN flight_booked AND return_flight_booked THEN 2
  						WHEN flight_booked THEN 1
  						ELSE 0
  						END) AS total_flights,
  				COUNT(hotel_booked) FILTER (WHERE hotel_booked = 'true') AS total_hotel_booked,
  				
  			 SUM((hotel_per_room_usd * nights*rooms) * (1 - COALESCE(hotel_discount_amount,0))) AS money_spent_hotel,
  			 SUM((base_fare_usd) * (1 - COALESCE(flight_discount_amount,0))) AS money_spent_filght,
         SUM((hotel_per_room_usd * nights*rooms) * (1 - COALESCE(hotel_discount_amount,0))) + SUM((base_fare_usd) * (1 - COALESCE(flight_discount_amount,0))) AS money_spent_booking,
  			 SUM(EXTRACT(DAY FROM departure_time - session_end)) AS total_time_before_trip,
  			 SUM(haversine_distance(home_airport_lat, home_airport_lon, destination_airport_lat, destination_airport_lon)) AS km_flown
	FROM session_level
  WHERE trip_id IS NOT NULL
  AND trip_id NOT IN (SELECT distinct trip_id
                     FROM session_level
                     WHERE cancellation --cancellation is True)
                     )
  GROUP BY user_id)
,
 user_level AS (
 SELECT
    user_id,
   -- session_id,
  --  trip_id,
    --birthdate,
    age,
    gender,
    married,
    has_children,
    home_country,
    home_city,
    home_airport,
    home_airport_lat,
    home_airport_lon,
    sign_up_date,
   
    SUM(page_clicks) AS total_clicks,
    SUM(nights) AS total_nights,
    SUM(rooms) AS total_rooms,
    ROUND(AVG(hotel_per_room_usd), 2) AS avg_hotel_per_room_usd,
    ROUND(AVG(base_fare_usd),2) AS avg_base_fare_usd,
    
    COUNT(DISTINCT session_id) AS session_count,
    ROUND(AVG(session_duration_in_seconds),0) AS avg_session_duration_in_seconds,
    
    
    COUNT(cancellation) FILTER (WHERE cancellation = 'true') AS total_cancellation,
    COUNT(flight_discount) FILTER (WHERE flight_discount = 'true') AS total_flight_with_discount,
    COUNT(hotel_discount) FILTER (WHERE hotel_discount = 'true') AS total_hotel_with_discount,
    ROUND(AVG(flight_discount_amount),2) AS avg_flight_discount,
    ROUND(AVG(hotel_discount_amount),2) AS avg_hotel_discount,
    ROUND(COUNT(flight_booked) FILTER (WHERE flight_booked = 'true') / COUNT(DISTINCT session_id)::NUMERIC , 2) AS con_rate_flights,
    ROUND(COUNT(hotel_booked) FILTER (WHERE hotel_booked = 'true') / COUNT(DISTINCT session_id)::NUMERIC , 2) AS con_rate_hotels,
    ROUND((COUNT(flight_booked) FILTER (WHERE flight_booked = 'true') + COUNT(hotel_booked) FILTER (WHERE hotel_booked = 'true')) / COUNT(DISTINCT session_id)::NUMERIC , 2) AS con_rate_combined,
    --COUNT(trip_id) AS total_trips,
    COUNT(return_flight_booked) FILTER (WHERE return_flight_booked = 'true') AS total_return_flight_booked,
  
  	CASE 
    		WHEN age BETWEEN 17 AND 25 THEN '17-25'
        WHEN age BETWEEN 26 AND 35 THEN '26-35'
        WHEN age BETWEEN 36 AND 50 THEN '36-50'
        ELSE '50+'
        END AS age_bucket,
    CASE
    		WHEN married = 'true' AND has_children = 'true' THEN 'Married With Children'
        WHEN married = 'true' AND has_children = 'false' THEN 'Married With No Children'
        WHEN married = 'false' AND has_children = 'true' THEN 'Single With Children'
        WHEN married = 'false' AND has_children = 'false' THEN 'Single With No Children'
        ELSE 'Unknown'
    END AS family_status    
       
FROM
    session_level
/*WHERE
		trip_id IS NOT NULL 
    AND
    trip_id NOT IN (SELECT
                    DISTINCT trip_id
                    FROM session_level
                    WHERE cancellation = 'true' )*/
GROUP BY 
    user_id,
    --session_id,
    --trip_id,
    --birthdate,
    age,
    gender,
    married,
    has_children,
    home_country,
    home_city,
    home_airport,
    home_airport_lat,
    home_airport_lon,
    sign_up_date,
    age_bucket,
    family_status
)

SELECT
			ul.*,
      tl.*
      
      
      
FROM
		user_level AS ul
LEFT JOIN
		trip_level AS tl
ON ul.user_id = tl.user_id
