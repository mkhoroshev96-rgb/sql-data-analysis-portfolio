-- 685. «Клієнт з ефектом ілюзії зростання»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date DESC) as rn_invert
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,case when rn_invert <= 3 THEN 'last_3'
	   else 'other' END as gradation
FROM level1
WHERE count_order >= 8),
level3 as(SELECT *
       ,ROUND(AVG(sum_chek) FILTER (WHERE gradation = 'last_3') OVER (partition by customer_id)::numeric,2) as avg_chek_last_3
	   ,ROUND(AVG(sum_chek) FILTER (WHERE gradation = 'other') OVER (partition by customer_id)::numeric,2) as avg_chek_other
	   ,ROUND(AVG(sum_chek) OVER (partition by customer_id)::numeric,2) as avg_chek
FROm level2)
SELECT *
FROM level3
WHERE avg_chek_last_3 > avg_chek_other AND avg_chek_other > avg_chek

-- 686. «Клієнт з ефектом стабільної деградації»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date DESC) as rn_invert
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,case when rn <= 3 THEN 'first_3'
	   when rn_invert <=3 THEN 'last_3'
	   else 'other'
	   END as gradation
FROm level1
WHERE count_order >= 9),
level3 as(SELECT *
       ,ROUND(AVG(sum_chek) FILTER (WHERE gradation = 'first_3') OVER (partition by customer_id)::numeric,2) as avg_chek_first_3
	   ,ROUND(AVG(sum_chek) FILTER (WHERE gradation = 'last_3') OVER (partition by customer_id)::numeric,2) as avg_chek_last_3
	   ,ROUND(AVG(sum_chek) OVER (partition by customer_id)::numeric,2) as avg_chek
FROm level2),
level4 as(SELECT *
       ,ROUND(ABS((avg_chek_first_3 - avg_chek) / avg_chek)::numeric,4) as diff_chek
FROM level3
WHERE avg_chek_first_3 > avg_chek_last_3)
SELECT *
FROm level4
WHERE diff_chek <= 0.05

-- 687. «Клієнт з ефектом прихованого перекосу»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIn order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,ROUND(AVG(sum_chek) OVER (partition by customer_id)::numeric,2) as avg_chek
FROM level1
WHERE count_order >= 10),
level3 as(SELECT *
       ,case when sum_chek > avg_chek THEN 'high_avg'
	   when sum_chek < avg_chek THEN 'low_avg'
	   when sum_chek = avg_chek THEN 'equal_avg'
	   END as gradation
FROm level2),
level4 as(SELECT *
       ,ROUND(AVG(sum_chek) FILTER (WHERE gradation = 'high_avg') OVER (partition by customer_id)::numeric,2) as avg_chek_high_avg
	   ,ROUND(AVG(sum_chek) FILTER (WHERE gradation = 'low_avg') OVER (partition by customer_id)::numeric,2) as avg_chek_low_avg
	   ,COUNT(order_id) FILTER (WHERE gradation = 'high_avg') OVER (partition by customer_id) as count_order_high_avg
	   ,COUNT(order_id) FILTER (WHERE gradation = 'low_avg') OVER (partition by customer_id) as count_order_low_avg
FROM level3)
SELECT *
FROm level4
WHERE avg_chek_high_avg > avg_chek_low_avg AND count_order_low_avg > count_order_high_avg

-- 688. «Клієнт з ефектом хибної стабільності»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,ntile(3) OVER (partition by customer_id order by order_date) as ntile_3
	   ,ROUND(AVG(sum_chek) OVER (partition by customer_id)::numeric,2) as avg_chek
FROm level1
WHERE count_order >= 12),
level3 as(SELECT *
       ,ROUND(AVG(sum_chek) FILTER (WHERE ntile_3 = 1) OVER (partition by customer_id)::numeric,2) as avg_chek_ntile_1
	   ,ROUND(AVG(sum_chek) FILTER (WHERE ntile_3 = 2) OVER (partition by customer_id)::numeric,2) as avg_chek_ntile_2
	   ,ROUND(AVG(sum_chek) FILTER (WHERE ntile_3 = 3) OVER (partition by customer_id)::numeric,2) as avg_chek_ntile_3
FROm level2),
level4 as(SELECT *
       ,ROUND(ABS((avg_chek_ntile_2 - avg_chek_ntile_1) / avg_chek_ntile_1)::numeric,2) as diff_chek_1_2
	   ,ROUND(ABS((avg_chek_ntile_3 - avg_chek_ntile_1) / avg_chek_ntile_1)::numeric,2) as diff_chek_1_3
	   ,ROUND(ABS((avg_chek_ntile_3 - avg_chek_ntile_2) / avg_chek_ntile_2)::numeric,2) as diff_chek_2_3
FROm level3)
SELECT *
FROm level4
WHERE diff_chek_1_2 <= 0.03 AND diff_chek_1_3 <= 0.03 AND diff_chek_2_3 <= 0.03

-- 689. «Клієнт з ефектом прихованого прискорення»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,ntile(3) OVER (partition by customer_id order by order_date) as ntile_3
	   ,ROUND(AVG(sum_chek) OVER (partition by customer_id)::numeric,2) as avg_chek
FROM level1
WHERE count_order >= 12),
level3 as(SELECT *
       ,ROUND(AVG(sum_chek) FILTER (WHERE ntile_3 = 1) OVER (partition by customer_id)::numeric,2) as avg_chek_ntile_1
	   ,ROUND(AVG(sum_chek) FILTER (WHERE ntile_3 = 3) OVER (partition by customer_id)::numeric,2) as avg_chek_ntile_3
FROm level2)
SELECT *
FROM level3
WHERE avg_chek_ntile_3 > avg_chek AND avg_chek_ntile_1 > avg_chek

-- 690. «Клієнт з ефектом внутрішньої компенсації»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT customer_id
       ,ROUND(AVG(sum_chek)::numeric,2) as avg_chek
	   ,percentile_cont(0.5) WITHIN GROUP (order by sum_chek) as median_chek
FROm level1
GROUP By customer_id),
level3 as(SELECT *
       ,ROUND(ABS((avg_chek - median_chek) / median_chek)::numeric,4) as diff_chek
FROm level1
JOIN level2 USING (customer_id)
WHERE count_order >= 10),
level4 as(SELECT *
       ,case when sum_chek > avg_chek THEN 'high_avg'
	   when sum_chek < avg_chek THEN 'low_avg'
	   when sum_chek = avg_chek THEN 'equal_avg'
	   END as gradation
FROm level3
WHERE diff_chek <= 0.05),
level5 as(SELECT *
       ,ROUND(AVG(sum_chek) FILTER (WHERE gradation = 'high_avg') OVER (partition by customer_id)::numeric,2) as avg_chek_high_avg
FROm level4),
level6 as(SELECT *
       ,ROUND((avg_chek_high_avg / avg_chek)::numeric,2) as diff_high_avg_and_avg
FROM level5)
SELECT *
FROm level6
WHERE diff_high_avg_and_avg >= 1.2

-- 691. «Клієнт з ефектом згасання цінності»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,row_NUMBER () OVER (partition by customer_id order by order_date) as rn
FROm orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
FROm level1
WHERE count_order >= 10),
level3 as(SELECT customer_id
       ,ROUND(corr(rn,sum_chek)::numeric,4) as corr_rn_chek
FROm level2
GROUP BY customer_id)
SELECT *
FROm level3
WHERE corr_rn_chek <= -0.6

-- 692. «Клієнт з ефектом інерційної динаміки»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROm orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,LEAD(sum_chek) OVER (partition by customer_id order by order_date) as next_chek
FROM level1
WHERE count_order >= 10),
level3 as(SELECT *
       ,ROUND(ABS((next_chek - sum_chek) / sum_chek)::numeric,2) as diff_chek
FROm level2
WHERE next_chek is not null),
level4 as(SELECT *
       ,case when diff_chek <= 0.5 THEN 1 ELSE 0 END as flag_diff_chek
FROm level3),
level5 as(SELECT *
       ,LEAD(flag_diff_chek,1) OVER (partition by customer_id order by order_date) as flag_2_diff_chek
	   ,LEAD(flag_diff_chek,2) OVER (partition by customer_id order by order_date) as flag_3_diff_chek
FROm level4),
level6 as(SELECT *
       ,case when flag_diff_chek = 1 AND flag_2_diff_chek = 1 AND flag_3_diff_chek = 1 THEN 'yes'
	   ELSE 'no' END as gradation
FROM level5)
SELECT *
FROm level6
WHERE gradation = 'yes'

-- 693. «Клієнт з ефектом локального максимуму, який не вплинув на історію»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROm orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
	   ,ROUND(AVG(sum_chek) OVER (partition by customer_id)::numeric,2) as avg_chek
FROm level1
WHERE count_order >= 9),
level3 as(SELECT *
       ,case when sum_chek > 1.7 * avg_chek THEN 1 ELSE 0 END as flag_chek
FROM level2),
level4 as(SELECT *
       ,SUM(flag_chek) OVER (partition by customer_id) as sum_flag_chek
FROM level3),
level5 as(SELECT *
       ,case when flag_chek = sum_flag_chek THEN 'max_order'
	   else 'other' END as gradation
FROm level4
WHERE sum_flag_chek = 1),
level6 as(SELECT *
       ,AVG(sum_chek) FILTER (WHERE gradation = 'other') OVER (partition by customer_id) as avg_chek_other
FROM level5),
level7 as(SELECT *
       ,ROUND(ABS((avg_chek_other - avg_chek) / avg_chek)::numeric,2) as diff_chek
FROm level6)
SELECT *
FROm level7
WHERE diff_chek <= 0.05

-- 694. «Клієнт з ефектом прихованої симетрії»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1- discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROm orders
JOIn order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
FROM level1
WHERE count_order >= 12),
level3 as(SELECT customer_id
       ,ROUND(AVG(sum_chek)::numeric,2) as avg_chek
	   ,percentile_cont(0.5) WITHIN GROUP (order by sum_chek) as median_chek
FROm level2
GROUP BY customer_id),
level4 as(SELECT *
       ,ROUND(ABS((avg_chek - median_chek) / median_chek)::numeric,4) as diff_avg_and_median
FROm level2
JOIN level3 USING (customer_id)),
level5 as(SELECT *
       ,case when sum_chek > median_chek THEN 'high_median'
	   when sum_chek < median_chek THEN 'low_median'
	   when sum_chek = median_chek THEN 'equal_median'
	   END as gradation
FROm level4
WHERE diff_avg_and_median >= 0.15),
level6 as(SELECT *
       ,ROUND(AVG(sum_chek) FILTER (WHERE gradation = 'low_median') OVER (partition by customer_id)::numeric,2) as avg_chek_low_median
	   ,ROUND(AVG(sum_chek) FILTER (WHERE gradation = 'high_median') OVER (partition by customer_id)::numeric,2) as avg_chek_high_median
FROm level5),
level7 as(SELECT *
       ,ROUND(ABS((avg_chek_high_median - avg_chek_low_median) / avg_chek_low_median)::numeric,4) as diff_high_low
FROM level6)
SELECT *
FROm level7
WHERE diff_high_low <= 0.05