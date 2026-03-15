-- 502. “Замовлення, яке зламало звичку”

WITh level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(quantity) as sum_quantity
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROm orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,SUM(sum_quantity) OVER (partition by customer_id order by order_date) as summ_cumm_quantity
	   ,SUM(sum_quantity) OVER (partition by customer_id) as total_quantity
	   ,COUNT(order_id) OVER (partition by customer_id order by order_date) as cumm_count
FROM level1
WHERE count_order >= 6),
level3 as(SELECT *
       ,summ_cumm_quantity - sum_quantity as before_sum
	   ,cumm_count - 1 as before_count
       ,total_quantity - summ_cumm_quantity  as after_sum
	   ,count_order - cumm_count as after_count
FROm level2),
level4 as(SELECT *
       ,ROUND((after_sum::numeric / after_count::numeric),2) as avg_after
	   ,ROUND((before_sum::numeric / before_count::numeric),2) as avg_before
FROM level3
WHERE after_sum > 0 AND after_count >= 1 AND before_sum > 0 AND before_count >= 1),
level5 as(SELECT *
       ,MIN(case when avg_after > avg_before THEN order_date END) OVER (partition by customer_id) as min_date
FROM level4)
SELECT *
FROm level5
WHERE order_date = min_date

-- 503. “Клієнт, який виглядає стабільним, але ним не є”

WITH level1 as(SELECT customer_id
        ,order_id
		,order_date
		,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
		,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,ROUND(AVG(sum_chek) OVER (partition by customer_id)::numeric,2) as avg_chek
	   ,ROUND(AVG(sum_chek) OVER ()::numeric,2) as global_avg_chek
	   ,ROUND(STDDEV(sum_chek) OVER (partition by customer_id)::numeric,2) as std_dev_chek
FROM level1
WHERE count_order >= 6),
level3 as(SELECT *
       ,ROUND(ABS((avg_chek - global_avg_chek) / global_avg_chek)::numeric,2) as diff_chek
	   ,ROUND((std_dev_chek / avg_chek),2) as cv
FROM level2),
level4 as(SELECT DISTINCT customer_id
       ,count_order
	   ,avg_chek
	   ,global_avg_chek
	   ,std_dev_chek
	   ,diff_chek
	   ,cv
	   ,ntile(10) OVER (order by cv DESC) as ntile_10 
FROM level3
ORDER BY ntile_10)
SELECT *
FROM level4
WHERE ntile_10 = 1 AND diff_chek <= 0.05

-- 504. “Нетипово дороге замовлення з незвичним домінуючим товаром”

WITH block1 as(WITh level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,ROUND(avg(sum_chek) OVER (partition by customer_id)::Numeric,2) as avg_chek
	   ,ROUND(STDDEV(sum_chek) OVER (partition by customer_id)::numeric,2) as std_dev_chek
FROM level1),
level3 as(SELECT *
       ,case when sum_chek > avg_chek + (2 * std_dev_chek) THEN 'yes'
	   ELSE 'no' END as flag_chek
FROM level2)
SELECT *
FROM level3
WHERE flag_chek = 'yes'),
block2 as(WITH level1 as(SELECT customer_id
       ,order_id
	   ,product_id
	   ,quantity
FROm orders
JOIN order_details USING (order_id)),
level2 as(SELECT customer_id
       ,order_id
       ,product_id
       ,SUM(quantity) as sum_quantity_product
FROm level1
GROUP BY customer_id, order_id, product_id),
level3 as(SELECT *
       ,ROW_NUMBER () OVER (partition by customer_id order by sum_quantity_product DESC) as rn
FROM level2)
SELECT *
FROM level3
WHERE rn > 5)
SELECT *
FROM block1 
JOIn block2 USING (customer_id, order_id) 

-- 505. «Клієнт з ефектом втраченої керованості»

WITH block1 as(WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,shipped_date - order_date as delivery_days
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,ROUND(AVG(sum_chek) OVER (partition by customer_id)::numeric,2) as avg_chek
	   ,ROUND(STDDEV(sum_chek) OVER (partition by customer_id)::numeric,2) as std_dev_chek
	   ,ROUND(AVG(delivery_days) OVER (partition by customer_id)::numeric,2) as avg_delivery
	   ,ROUND(STDDEV(delivery_days) OVER (partition by customer_id)::numeric,2) as std_dev_delivery
FROm level1
WHERE count_order >= 8),
level3 as(SELECT *
       ,ROUND(((sum_chek - avg_chek) / std_dev_chek)::numeric,2) as z_chek
	   ,ROUND(((delivery_days - avg_delivery) / std_dev_delivery)::numeric,2) as z_delivery
FROm level2),
level4 as(SELECT *
       ,ABS(z_chek - z_delivery) as gap
	   ,ntile(4) OVER (partition by customer_id order by order_date) as ntile_4
FROm level3),
level5 as(SELECT customer_id
       ,ROUND(AVG(gap) FILTER (WHERE ntile_4 = 1)::numeric,2) as avg_gap_1
	   ,ROUND(AVG(gap) FILTER (WHERE ntile_4 = 2)::numeric,2) as avg_gap_2
	   ,ROUND(AVG(gap) FILTER (WHERE ntile_4 = 3)::numeric,2) as avg_gap_3
	   ,ROUND(AVG(gap) FILTER (WHERE ntile_4 = 4)::numeric,2) as avg_gap_4
FROM level4
GROUP By customer_id),
level6 as(SELECT *
       ,case when avg_gap_3 > avg_gap_1 AND avg_gap_3 > avg_gap_2 AND avg_gap_3 > avg_gap_4 THEN 'yes'
	   ELSE 'no' END as gradation
FROM level5)
SELECT *
FROm level6
WHERE gradation = 'yes'),
block2 as(WITH level1 as(SELECT customer_id
       ,order_id
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as order_chek
FROm orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id),
level2 as(SELECT *
       ,ROUND(AVG(order_chek) OVER (partition by customer_id)::numeric,2) as avg_chek
	   ,ROUND(AVG(order_chek) OVER ()::numeric,2) as global_avg_chek
FROM level1),
level3 as(SELECT *
       ,ROUND(ABS((avg_chek - global_avg_chek) / global_avg_chek)::numeric,2) as diff_chek
FROm level2)
SELECT DISTINCT customer_id
       ,diff_chek
FROm level3
WHERE diff_chek <= 0.1)
SELECT *
FROm block1
JOIN block2 USING (customer_id)

-- 506. «Клієнт з ефектом миттєвого розчарування»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROm orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,ROUND(AVG(sum_chek) OVER (partition by customer_id)::numeric,2) as avg_chek
FROM level1
WHERE count_order >= 6),
level3 as(SELECT *
       ,case when sum_chek > avg_chek THEN 'good'
	   ELSE 'other' END as good_other
	   ,LEAD(sum_chek) OVER (partition by customer_id) as next_chek
FROM level2),
level4 as(SELECT *
       ,ROUND(AVG(next_chek) FILTER (WHERE  good_other = 'good') OVER (partition by customer_id)::numeric,2) as avg_chek_after_good
FROM level3
WHERE good_other = 'good')
SELECT *
FROM level4
WHERE avg_chek_after_good < avg_chek